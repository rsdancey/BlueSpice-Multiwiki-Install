/* eslint-disable */
// Behavioural check for the ConfigManager Authentication tab.
//
// scripts/patch-bluespice.sh reconnects the "change" chain that arms the Save
// button when an already-saved PluggableAuth entry is edited. A SKIP line from
// that script proves a patch did not apply; it cannot prove the result behaves.
// This does: it loads the real widget sources out of a wiki container against a
// minimal stub of the OO.ui / jQuery surface they touch, and asserts that edits
// propagate while the add-new form stays silent.
//
// Run by verify_configmanager_patches() in lib/verify-patches.sh, which stages
// oojs.js and the four widget sources next to this file. Expects them in the
// same directory. Exits 0 if every assertion passes, 1 otherwise.
'use strict';

const fs = require( 'fs' );
const path = require( 'path' );
const dir = __dirname;

for ( const required of [ 'oojs.js', 'JsonArrayInputWidget.js', 'ObjectInputWidget.js',
	'KeyValueInputWidget.js', 'KeyObjectInputWidget.js' ] ) {
	if ( !fs.existsSync( path.join( dir, required ) ) ) {
		console.error( 'missing source: ' + required );
		process.exit( 2 );
	}
}

// --- real OOJS (DOM-free) ---------------------------------------------------
global.window = global;
// oojs.js is UMD: under Node it assigns module.exports rather than global.OO.
const OO = require( path.join( dir, 'oojs.js' ) );
global.OO = OO;

// --- minimal jQuery stub ----------------------------------------------------
function $el() {
	const o = {
		_children: [],
		addClass() { return o; },
		append() { return o; },
		prepend() { return o; },
		remove() { return o; },
		on() { return o; },
		html() { return o; },
		find() { return $el(); },
		clone() { return $el(); },
		is() { return false; },
		length: 0
	};
	return o;
}
const $ = () => $el();
$.isEmptyObject = ( obj ) => !obj || Object.keys( obj ).length === 0;
$.type = ( v ) => ( v === null ? 'null' : Array.isArray( v ) ? 'array' : typeof v );
// jQuery-style Deferred (the widgets use .done()/.fail(), not native promises).
$.Deferred = function () {
	let state = 'pending';
	const dones = [], fails = [];
	const api = {
		done( cb ) { if ( state === 'resolved' ) { cb(); } else { dones.push( cb ); } return api; },
		fail( cb ) { if ( state === 'rejected' ) { cb(); } else { fails.push( cb ); } return api; },
		promise() { return api; },
		resolve() { if ( state === 'pending' ) { state = 'resolved'; dones.forEach( ( cb ) => cb() ); } return api; },
		reject() { if ( state === 'pending' ) { state = 'rejected'; fails.forEach( ( cb ) => cb() ); } return api; }
	};
	return api;
};
global.jQuery = global.$ = $;

// --- minimal mw / bs --------------------------------------------------------
global.mediaWiki = { message: () => ( { text: () => 'stub', plain: () => 'stub' } ) };
global.blueSpice = { ui: { widget: {} } };

// --- minimal OO.ui ----------------------------------------------------------
// Only what the four widget sources actually call. setValue()/emit semantics
// mirror OOUI: a change event fires only when the value actually changes.
OO.ui = {};

OO.ui.Widget = function () {
	OO.EventEmitter.call( this );
	this.$element = $el();
	this.disabled = false;
};
OO.initClass( OO.ui.Widget );
OO.mixinClass( OO.ui.Widget, OO.EventEmitter );

OO.ui.InputWidget = function ( cfg ) {
	cfg = cfg || {};
	OO.ui.Widget.call( this, cfg );
	this.$input = $el();
	this.value = cfg.value !== undefined ? cfg.value : '';
};
OO.inheritClass( OO.ui.InputWidget, OO.ui.Widget );
// Mirrors OOUI: setValue emits "change" only when the value actually changes.
OO.ui.InputWidget.prototype.setValue = function ( v ) {
	v = v === undefined || v === null ? '' : v;
	if ( this.value !== v ) {
		this.value = v;
		this.emit( 'change', this.value );
	}
	return this;
};
OO.ui.InputWidget.prototype.getValue = function () { return this.value; };
OO.ui.InputWidget.prototype.setValidityFlag = function () { return this; };
OO.ui.InputWidget.prototype.getValidity = function () { return $.Deferred().resolve().promise(); };

OO.ui.TextInputWidget = function ( cfg ) { OO.ui.InputWidget.call( this, cfg ); };
OO.inheritClass( OO.ui.TextInputWidget, OO.ui.InputWidget );

OO.ui.MultilineTextInputWidget = function ( cfg ) { OO.ui.TextInputWidget.call( this, cfg ); };
OO.inheritClass( OO.ui.MultilineTextInputWidget, OO.ui.TextInputWidget );

OO.ui.NumberInputWidget = function ( cfg ) { OO.ui.InputWidget.call( this, cfg ); };
OO.inheritClass( OO.ui.NumberInputWidget, OO.ui.InputWidget );

OO.ui.CheckboxInputWidget = function ( cfg ) { OO.ui.InputWidget.call( this, cfg ); this.selected = false; };
OO.inheritClass( OO.ui.CheckboxInputWidget, OO.ui.InputWidget );
OO.ui.CheckboxInputWidget.prototype.setSelected = function ( s ) {
	if ( this.selected !== !!s ) { this.selected = !!s; this.emit( 'change', this.selected ); }
};
OO.ui.CheckboxInputWidget.prototype.isSelected = function () { return this.selected; };

OO.ui.ButtonWidget = function () { OO.ui.Widget.call( this ); };
OO.inheritClass( OO.ui.ButtonWidget, OO.ui.Widget );

OO.ui.LabelWidget = function () { OO.ui.Widget.call( this ); };
OO.inheritClass( OO.ui.LabelWidget, OO.ui.Widget );

OO.ui.FieldLayout = function ( widget ) { OO.ui.Widget.call( this ); this.widget = widget; };
OO.inheritClass( OO.ui.FieldLayout, OO.ui.Widget );
OO.ui.FieldLayout.prototype.setLabel = function () { return this; };

OO.ui.FieldsetLayout = function ( cfg ) { OO.ui.Widget.call( this ); this.items = ( cfg || {} ).items || []; };
OO.inheritClass( OO.ui.FieldsetLayout, OO.ui.Widget );
OO.ui.FieldsetLayout.prototype.addItems = function ( items ) { this.items = items; return this; };

// --- load the real widget sources ------------------------------------------
for ( const f of [ 'JsonArrayInputWidget', 'ObjectInputWidget', 'KeyValueInputWidget', 'KeyObjectInputWidget' ] ) {
	eval( fs.readFileSync( path.join( dir, f + '.js' ), 'utf8' ) );
}

// --- test -------------------------------------------------------------------
const objectConfiguration = {
	plugin: { type: 'text', widget: { required: true }, label: 'Plugin name' },
	data: { type: 'json', widget: { required: false }, label: 'Data object (JSON)' },
	groupsyncs: { type: 'json', widget: { required: false }, label: 'Group sync settings (JSON)' }
};

const widget = new global.blueSpice.ui.widget.KeyObjectInputWidget( {
	value: {
		'Login with Google': {
			plugin: 'OpenIDConnect',
			data: { providerURL: 'https://accounts.google.com', clientID: 'abc' },
			groupsyncs: {}
		}
	},
	objectConfiguration: objectConfiguration,
	keyLabel: 'Button label',
	allowAdditions: true,
	labelsOnlyOnFirst: true,
	valueRequired: true
} );

let fired = 0;
widget.on( 'change', () => { fired++; } );

let failures = 0;
function check( name, cond, extra ) {
	if ( cond ) {
		console.log( '  PASS  ' + name );
	} else {
		failures++;
		console.log( '  FAIL  ' + name + ( extra ? '  -> ' + extra : '' ) );
	}
}

console.log( 'existing entry is registered' );
check( 'one row in addedWidgets', widget.addedWidgets.length === 1, 'got ' + widget.addedWidgets.length );

console.log( '\nconstruction must not arm Save' );
check( 'no change event during build', fired === 0, 'fired=' + fired );

console.log( '\nediting a saved entry must arm Save' );
const row = widget.addedWidgets[ 0 ].valueWidget;

fired = 0;
row.widgets.plugin.setValue( 'OpenIDConnectChanged' );
check( 'text sub-field (Plugin name) propagates', fired > 0, 'fired=' + fired );

fired = 0;
row.widgets.data.widget.setValue( '{"providerURL":"https://example.com"}' );
check( 'JSON sub-field (Data object) propagates', fired > 0, 'fired=' + fired );

fired = 0;
row.widgets.groupsyncs.widget.setValue( '{"a":"b"}' );
check( 'JSON sub-field (Group sync) propagates', fired > 0, 'fired=' + fired );

fired = 0;
widget.addedWidgets[ 0 ].keyWidget.setValue( 'Login with Google SSO' );
check( 'key field (Button label) propagates', fired > 0, 'fired=' + fired );

console.log( '\nthe add-new form must NOT arm Save before the check button' );
fired = 0;
widget.addForm.inputs.key.setValue( 'Second provider' );
widget.addForm.inputs.value.widgets.plugin.setValue( 'Ldap' );
widget.addForm.inputs.value.widgets.data.widget.setValue( '{"x":1}' );
check( 'typing in add form stays silent', fired === 0, 'fired=' + fired );

console.log( '\nvalue still round-trips' );
const val = widget.getValue();
const entry = val[ 'Login with Google SSO' ];
check( 'entry present under edited key', !!entry, JSON.stringify( Object.keys( val ) ) );
check( 'plugin reflects the edit', entry && entry.plugin === 'OpenIDConnectChanged', entry && entry.plugin );
check( 'data parsed back to an object',
	entry && entry.data && entry.data.providerURL === 'https://example.com',
	JSON.stringify( entry && entry.data ) );

console.log( '\ncommitting the add form still works' );
fired = 0;
widget.onAddClick();
setTimeout( () => {
	check( 'onAddClick emits change', fired > 0, 'fired=' + fired );
	check( 'second entry added', widget.addedWidgets.length === 2, 'rows=' + widget.addedWidgets.length );
	console.log( '\n' + ( failures === 0 ? 'ALL PASS' : failures + ' FAILURE(S)' ) );
	process.exit( failures === 0 ? 0 : 1 );
}, 50 );
