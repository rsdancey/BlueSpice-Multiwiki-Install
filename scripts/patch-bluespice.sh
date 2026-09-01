#!/bin/bash
# Re-apply local fixes to BlueSpice extension files inside the container.
#
# /app is ephemeral: it is reset to the image contents every time a container is
# created, which happens on every upgrade. Patches to files under /app therefore
# have to be re-applied on every container start, from the entrypoint wrapper,
# before the web/task process is exec'd.
#
# Every patch is idempotent (it checks for the fixed text first) and never fatal:
# a patch whose search text no longer matches — because BlueSpice fixed it
# upstream, or moved the code — is reported and skipped so the container still
# starts. Review the SKIP lines after a version bump and drop patches that
# upstream has taken over.

WIKI_ROOT=/app/bluespice/w

# apply_patch <label> <file> <search> <replace>
apply_patch() {
    local label="$1" file="$2" search="$3" replace="$4"

    if [[ ! -f "$file" ]]; then
        echo "patch-bluespice: SKIP ${label} — ${file} not found" >&2
        return 0
    fi

    PATCH_SEARCH="$search" PATCH_REPLACE="$replace" php -r '
        $file = $argv[1];
        $search = getenv( "PATCH_SEARCH" );
        $replace = getenv( "PATCH_REPLACE" );
        $content = file_get_contents( $file );
        if ( $content === false ) { exit( 4 ); }
        if ( strpos( $content, $replace ) !== false ) { exit( 2 ); }
        if ( strpos( $content, $search ) === false ) { exit( 3 ); }
        if ( file_put_contents( $file, str_replace( $search, $replace, $content ) ) === false ) {
            exit( 4 );
        }
        exit( 0 );
    ' "$file"

    case $? in
        0) echo "patch-bluespice: applied ${label}" >&2 ;;
        2) echo "patch-bluespice: already applied ${label}" >&2 ;;
        3) echo "patch-bluespice: SKIP ${label} — search text not found (upstream changed?)" >&2 ;;
        *) echo "patch-bluespice: FAILED ${label} — could not write ${file}" >&2 ;;
    esac
    return 0
}

# --- ConfigManager writes back a corrupted PluggableAuth config --------------
# KeyObjectInputWidget::getValueInput() re-encodes the whole entry into every
# TYPE_JSON sub-field instead of that field's own value. Reopening
# Configuration -> Authentication therefore shows "Data object (JSON)" holding
# the entire entry and "Group sync settings (JSON)" holding that again, nested.
# Saving from that form writes the corruption back and wipes the OAuth config.
apply_patch \
    "KeyObjectInputWidget JSON sub-field encoding" \
    "${WIKI_ROOT}/extensions/BlueSpiceFoundation/src/Html/OOUI/KeyObjectInputWidget.php" \
    ': FormatJson::encode( $value );' \
    ': FormatJson::encode( $value[$key] );'

# --- ConfigManager loses the selected tab after every save -------------------
# The booklet's select handler stores the page *name*, but this check compares
# it against an array of ConfigPage *objects*, so it never matches and every
# store reload falls through to selectFirstSelectablePage(). After saving you
# are dropped back on the first tab (Administration) instead of the tab you
# were editing, which makes a successful save look like it did nothing.
apply_patch \
    "ConfigManager selected-tab restore" \
    "${WIKI_ROOT}/extensions/BlueSpiceConfigManager/resources/ui/panel/ConfigManager.js" \
    $'\tif ( !this.selectedPage || !configPages.includes( this.selectedPage ) ) {\n\t\tthis.bookletLayout.selectFirstSelectablePage();\n\t\tthis.selectedPage = this.bookletLayout.getCurrentPage();\n\t} else {' \
    $'\tconst configPageNames = configPages.map( ( configPage ) => configPage.getName() );\n\tif ( !this.selectedPage || !configPageNames.includes( this.selectedPage ) ) {\n\t\tthis.bookletLayout.selectFirstSelectablePage();\n\t\tthis.selectedPage = this.bookletLayout.getCurrentPage().getName();\n\t} else {'

# --- Editing a saved entry never re-enables Save -----------------------------
# ConfigPage.js enables Save from the config widget's "change" event, but
# KeyValueInputWidget only emits it from onAddClick()/onDeleteClick(). Nothing
# subscribes to the inputs of an entry that already exists, so editing a saved
# OAuth config is invisible to the form and Save stays greyed out — the entry
# has to be deleted and re-added instead. Three links are missing; all three
# have to be restored for an edit to reach the Save button:
#
#   JsonArrayInputWidget -> its own inner text widget
#   ObjectInputWidget    -> its per-key sub-widgets
#   KeyValueInputWidget  -> the key/value widgets of each existing row
#
# Each connect() is made after the widget's initial value is set, so populating
# the form on page load does not emit change and does not arm Save on its own.

apply_patch \
    "JsonArrayInputWidget change propagation" \
    "${WIKI_ROOT}/extensions/BlueSpiceFoundation/resources/bluespice.oojs/ui/widget/JsonArrayInputWidget.js" \
    $'\t\tthis.$element.addClass( \'bs-ooui-widget-jsonArrayInputWidget\' );\n\t\tthis.$element.append( this.widget.$element );' \
    $'\t\tthis.$element.addClass( \'bs-ooui-widget-jsonArrayInputWidget\' );\n\t\tthis.$element.append( this.widget.$element );\n\n\t\t// Typing goes into the inner widget, which emits "change" on itself and\n\t\t// not on this wrapper. Re-emit so subscribers see JSON edits at all.\n\t\tthis.widget.connect( this, {\n\t\t\tchange: function () {\n\t\t\t\tthis.emit( \'change\', this.getValue() );\n\t\t\t}\n\t\t} );'

apply_patch \
    "ObjectInputWidget change propagation" \
    "${WIKI_ROOT}/extensions/BlueSpiceFoundation/resources/bluespice.oojs/ui/widget/ObjectInputWidget.js" \
    $'\t\t\tif ( this.values.hasOwnProperty( key ) ) {\n\t\t\t\tthis.setWidgetValue( this.widgets[ key ], this.values[ key ] );\n\t\t\t}\n\t\t\tthis.layouts.push( new OO.ui.FieldLayout( this.widgets[ key ], {' \
    $'\t\t\tif ( this.values.hasOwnProperty( key ) ) {\n\t\t\t\tthis.setWidgetValue( this.widgets[ key ], this.values[ key ] );\n\t\t\t}\n\t\t\t// Connected after the initial value is set, so building the form\n\t\t\t// does not emit change.\n\t\t\tthis.widgets[ key ].connect( this, {\n\t\t\t\tchange: function () {\n\t\t\t\t\tthis.emit( \'change\', this.getValue() );\n\t\t\t\t}\n\t\t\t} );\n\t\t\tthis.layouts.push( new OO.ui.FieldLayout( this.widgets[ key ], {'

apply_patch \
    "KeyValueInputWidget entry change propagation" \
    "${WIKI_ROOT}/extensions/BlueSpiceFoundation/resources/bluespice.oojs/ui/widget/KeyValueInputWidget.js" \
    $'\t\t\tcfg.deleteWidget.$element.on( \'click\', {\n\t\t\t\tkeyWidget: keyInput,\n\t\t\t\tdeleteWidget: cfg.deleteWidget\n\t\t\t}, this.onDeleteClick.bind( this ) );\n\t\t}' \
    $'\t\t\tcfg.deleteWidget.$element.on( \'click\', {\n\t\t\t\tkeyWidget: keyInput,\n\t\t\t\tdeleteWidget: cfg.deleteWidget\n\t\t\t}, this.onDeleteClick.bind( this ) );\n\n\t\t\t// Only for existing entries (addToWidgets). The add-new form must NOT\n\t\t\t// arm Save while it is being typed into: its content is not part of\n\t\t\t// getValue() until the check button commits it via onAddClick().\n\t\t\tkeyInput.connect( this, {\n\t\t\t\tchange: function () {\n\t\t\t\t\tthis.emit( \'change\', this );\n\t\t\t\t}\n\t\t\t} );\n\t\t\tvalueInput.connect( this, {\n\t\t\t\tchange: function () {\n\t\t\t\t\tthis.emit( \'change\', this );\n\t\t\t\t}\n\t\t\t} );\n\t\t}'

exit 0
