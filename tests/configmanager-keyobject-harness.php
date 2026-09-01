<?php
/**
 * Behavioural check for the KeyObjectInputWidget patch applied by
 * scripts/patch-bluespice.sh.
 *
 * KeyObjectInputWidget::getValueInput() renders one input per sub-field of a
 * config entry. On pristine BlueSpice 5.2.6 every TYPE_JSON sub-field is filled
 * with FormatJson::encode( $value ) — the whole entry — instead of that field's
 * own value, and the result is assigned back into $value[$key], so the
 * corruption compounds across the loop. Reopening Configuration ->
 * Authentication then shows the entire entry inside "Data object (JSON)" and
 * that again, nested, inside "Group sync settings (JSON)"; saving from that
 * form writes the garbage back and empties the OAuth config.
 *
 * This drives the real method with reflection — the class is only constructible
 * inside a full ConfigManager request — and asserts each sub-field input carries
 * its own value. Exits 0 if every assertion passes, 1 otherwise.
 *
 * Run through the wiki's maintenance runner inside a wiki container.
 */

$IP = getenv( 'MW_INSTALL_PATH' ) ?: '/app/bluespice/w';
require_once "$IP/maintenance/Maintenance.php";

class ConfigManagerKeyObjectHarness extends Maintenance {

	/** @var int */
	private $failures = 0;

	public function execute() {
		$class = \BlueSpice\Html\OOUI\KeyObjectInputWidget::class;
		if ( !class_exists( $class ) ) {
			$this->output( "harness: $class not found\n" );
			exit( 2 );
		}

		// The three sub-field types PluggableAuth's config definition uses. It is
		// the only definition in the distribution with TYPE_JSON sub-fields, and
		// two of them, which is what makes the compounding visible.
		$objectConfiguration = [
			'plugin' => [ 'type' => 'text', 'label' => 'Plugin name' ],
			'data' => [ 'type' => 'json', 'label' => 'Data object (JSON)' ],
			'groupsyncs' => [ 'type' => 'json', 'label' => 'Group sync settings (JSON)' ],
		];
		$entry = [
			'plugin' => 'OpenIDConnect',
			'data' => [ 'clientId' => 'abc123', 'clientSecret' => 'shh' ],
			'groupsyncs' => [ 'type' => 'oidc' ],
		];

		$reflection = new ReflectionClass( $class );
		$widget = $reflection->newInstanceWithoutConstructor();

		$property = $reflection->getProperty( 'objectConfiguration' );
		$property->setAccessible( true );
		$property->setValue( $widget, $objectConfiguration );

		$method = $reflection->getMethod( 'getValueInput' );
		$method->setAccessible( true );
		$inputs = $method->invoke( $widget, $entry );

		$this->check(
			'one input per sub-field',
			count( $inputs ) === count( $objectConfiguration ),
			'got ' . count( $inputs )
		);
		if ( count( $inputs ) !== count( $objectConfiguration ) ) {
			$this->finish();
		}

		$values = [];
		foreach ( array_keys( $objectConfiguration ) as $i => $key ) {
			$values[$key] = $inputs[$i]->getField()->getValue();
		}

		$this->check(
			'text sub-field carries its own value',
			$values['plugin'] === 'OpenIDConnect',
			$this->show( $values['plugin'] )
		);
		$this->check(
			'JSON sub-field (data) carries its own value',
			$this->jsonEquals( $values['data'], $entry['data'] ),
			$this->show( $values['data'] )
		);
		$this->check(
			'JSON sub-field (groupsyncs) carries its own value',
			$this->jsonEquals( $values['groupsyncs'], $entry['groupsyncs'] ),
			$this->show( $values['groupsyncs'] )
		);

		// The pristine bug is visible as the entry's other keys leaking into a
		// JSON sub-field. Assert directly so the failure names the cause.
		foreach ( [ 'data', 'groupsyncs' ] as $key ) {
			$this->check(
				"JSON sub-field ($key) does not swallow the whole entry",
				strpos( (string)$values[$key], 'OpenIDConnect' ) === false,
				$this->show( $values[$key] )
			);
		}

		$this->finish();
	}

	/**
	 * @param string $actual
	 * @param array $expected
	 * @return bool
	 */
	private function jsonEquals( $actual, array $expected ) {
		$decoded = json_decode( (string)$actual, true );
		return $decoded === $expected;
	}

	/**
	 * @param mixed $value
	 * @return string
	 */
	private function show( $value ) {
		$str = is_string( $value ) ? $value : var_export( $value, true );
		return strlen( $str ) > 120 ? substr( $str, 0, 117 ) . '...' : $str;
	}

	/**
	 * @param string $name
	 * @param bool $cond
	 * @param string $extra
	 */
	private function check( $name, $cond, $extra = '' ) {
		if ( $cond ) {
			$this->output( "  PASS  $name\n" );
			return;
		}
		$this->failures++;
		$this->output( "  FAIL  $name" . ( $extra !== '' ? "  -> $extra" : '' ) . "\n" );
	}

	private function finish() {
		$this->output( "\n" . ( $this->failures === 0 ? "ALL PASS\n" : "{$this->failures} FAILURE(S)\n" ) );
		exit( $this->failures === 0 ? 0 : 1 );
	}
}

$maintClass = ConfigManagerKeyObjectHarness::class;
require_once RUN_MAINTENANCE_IF_MAIN;
