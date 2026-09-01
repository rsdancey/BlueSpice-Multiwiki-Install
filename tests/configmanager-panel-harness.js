/* eslint-disable */
// Behavioural check for the ConfigManager selected-tab restore.
//
// scripts/patch-bluespice.sh fixes setupBooklet(), which on pristine BlueSpice
// 5.2.6 compares the selected page *name* against an array of ConfigPage
// *objects*. The check never matches, so every store reload falls through to
// selectFirstSelectablePage() and drops you back on Administration instead of
// the tab you were editing — which makes a successful save look like it did
// nothing. A SKIP line from that script proves a patch did not apply; it cannot
// prove the result behaves. This does.
//
// The real ConfigManager.js is evaluated with bs/OO/$/mw supplied rather than
// edited: it is a ResourceLoader module whose require() calls use paths relative
// to the extension, which Node cannot resolve. Only setupBooklet() is driven;
// the booklet and the config pages it builds are stubs, since they are not what
// the patch touches.
//
// Run by verify_configmanager_patches() in lib/verify-patches.sh, which stages
// oojs.js and ConfigManager.js next to this file. Expects them in the same
// directory. Exits 0 if every assertion passes, 1 otherwise.
'use strict';

const fs = require( 'fs' );
const path = require( 'path' );
const dir = __dirname;

for ( const required of [ 'oojs.js', 'ConfigManager.js' ] ) {
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
OO.ui = { Widget: function () {} };

// --- minimal jQuery stub ----------------------------------------------------
function $el() {
	const o = {
		empty() { return o; },
		append() { return o; },
		prepend() { return o; },
		addClass() { return o; }
	};
	return o;
}
const $ = ( arg ) => ( arg && typeof arg.empty === 'function' ? arg : $el() );
global.jQuery = global.$ = $;

// --- minimal mw / bs / OOJSPlus ---------------------------------------------
const mw = { message: () => ( { text: () => 'stub' } ) };
const OOJSPlus = { ui: { data: { store: { RemoteStore: function () {} } } } };

const bs = {
	util: {
		registerNamespace: function ( ns ) {
			let node = bs;
			for ( const part of ns.split( '.' ).slice( 1 ) ) {
				node[ part ] = node[ part ] || {};
				node = node[ part ];
			}
		}
	}
};
bs.util.registerNamespace( 'bs.configmanager.ui.pages' );
bs.util.registerNamespace( 'bs.configmanager.ui.booklet' );

// A config page is identified by its name; that is the whole contract
// setupBooklet() depends on.
bs.configmanager.ui.pages.ConfigPage = function ( key ) {
	this.name = key;
	this.$element = $el();
};
bs.configmanager.ui.pages.ConfigPage.prototype.getName = function () {
	return this.name;
};
bs.configmanager.ui.pages.ConfigPage.prototype.connect = function () {};
bs.configmanager.ui.pages.ConfigPage.prototype.infuseWidgets = function () {};

// Records what setupBooklet() asked it to do, so the assertions can tell a
// restore apart from a fallback.
bs.configmanager.ui.booklet.ConfigBooklet = function () {
	this.$element = $el();
	this.pages = [];
	this.current = null;
	this.handlers = null;
	this.firstSelected = 0;
	this.setPageCalls = [];
};
bs.configmanager.ui.booklet.ConfigBooklet.prototype.connect = function ( ctx, handlers ) {
	this.ctx = ctx;
	this.handlers = handlers;
};
bs.configmanager.ui.booklet.ConfigBooklet.prototype.addPages = function ( pages ) {
	this.pages = pages;
};
bs.configmanager.ui.booklet.ConfigBooklet.prototype.selectFirstSelectablePage = function () {
	this.firstSelected++;
	this.current = this.pages[ 0 ];
};
bs.configmanager.ui.booklet.ConfigBooklet.prototype.getCurrentPage = function () {
	return this.current;
};
bs.configmanager.ui.booklet.ConfigBooklet.prototype.setPage = function ( name ) {
	this.setPageCalls.push( name );
	this.current = this.pages.find( ( page ) => page.getName() === name ) || this.current;
};
// Mirrors the real booklet emitting "select" when the user clicks a tab.
bs.configmanager.ui.booklet.ConfigBooklet.prototype.emitSelect = function ( name ) {
	this.handlers.select.call( this.ctx, { data: name } );
};

// --- load the real ConfigManager.js -----------------------------------------
const src = fs.readFileSync( path.join( dir, 'ConfigManager.js' ), 'utf8' );
new Function( 'bs', 'OO', '$', 'jQuery', 'mw', 'OOJSPlus', 'require', src )(
	bs, OO, $, $, mw, OOJSPlus, () => ( {} )
);

// --- drive setupBooklet() ---------------------------------------------------
// Administration sorts first, so a broken restore always lands there — which is
// exactly the symptom being guarded against.
const PAGES = [ 'authentication', 'administration', 'search' ];
const FIRST = 'administration';

function newPanel() {
	const panel = Object.create( bs.configmanager.ui.panel.ConfigManager.prototype );
	panel.$content = $el();
	panel.pathnames = {};
	panel.activePath = 'bs';
	panel.paths = { bs: PAGES.slice() };
	panel.data = [];
	return panel;
}

let failures = 0;
function check( name, cond, extra ) {
	if ( cond ) {
		console.log( '  PASS  ' + name );
	} else {
		failures++;
		console.log( '  FAIL  ' + name + ( extra ? '  -> ' + extra : '' ) );
	}
}

// 1. First load: nothing selected yet, so the first page is chosen.
const panel = newPanel();
panel.setupBooklet();
check( 'first load falls back to the first page',
	panel.bookletLayout.firstSelected === 1,
	'firstSelected=' + panel.bookletLayout.firstSelected );
check( 'selectedPage is stored as a name, not a page object',
	typeof panel.selectedPage === 'string',
	typeof panel.selectedPage );
check( 'selectedPage is the first page',
	panel.selectedPage === FIRST,
	String( panel.selectedPage ) );

// 2. Clicking a tab stores that page, and a reload must come back to it. This
//    is the round trip pristine breaks: it stores an object, so the next reload
//    never matches and drops back to the first page.
panel.bookletLayout.emitSelect( 'authentication' );
check( 'clicking a tab stores its name',
	panel.selectedPage === 'authentication',
	String( panel.selectedPage ) );

panel.setupBooklet();
check( 'reload restores the selected tab',
	panel.bookletLayout.setPageCalls[ 0 ] === 'authentication',
	JSON.stringify( panel.bookletLayout.setPageCalls ) );
check( 'reload does not fall back to the first page',
	panel.bookletLayout.firstSelected === 0,
	'firstSelected=' + panel.bookletLayout.firstSelected );

// 3. A page that no longer exists must fall back rather than throw.
const stale = newPanel();
stale.selectedPage = 'a-page-that-was-removed';
stale.setupBooklet();
check( 'a stale selection falls back to the first page',
	stale.bookletLayout.firstSelected === 1 && stale.selectedPage === FIRST,
	String( stale.selectedPage ) );

console.log( '\n' + ( failures === 0 ? 'ALL PASS' : failures + ' FAILURE(S)' ) );
process.exit( failures === 0 ? 0 : 1 );
