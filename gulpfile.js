/**
 * an example gulpfile to make ant-less existdb package builds a reality
 */
const { src, dest, watch, series, parallel, lastRun } = require('gulp')
const { createClient } = require('@existdb/gulp-exist')
const zip = require("gulp-zip")
const replace = require('@existdb/gulp-replace-tmpl')
const rename = require('gulp-rename')
const del = require('delete')

const pkg = require('./package.json')
const { version, license } = pkg

// read metadata from .existdb.json
const {package, servers} = require('./.existdb.json')
const replacements = [package, { version, license }]

const packageUri = package.namespace
const serverInfo = servers.localhost
const target = serverInfo.root

const connectionOptions = {
    basic_auth: {
        user: serverInfo.user,
        pass: serverInfo.password
    }
}
const existClient = createClient(connectionOptions);

/**
 * Use the `delete` module directly, instead of using gulp-rimraf
 */
function clean (cb) {
    del(['build','dist'], cb);
}
exports.clean = clean

/**
 * replace placeholders
 * in src/repo.xml.tmpl and
 * output to build/repo.xml
 */
function templates () {
    return src('src/*.tmpl')
        .pipe(replace(replacements, {unprefixed: true}))
        .pipe(rename(path => { path.extname = "" }))
        .pipe(dest('build/'))
}
exports.templates = templates

function watchTemplates () {
    watch('src/*.tmpl', series(templates))
}
exports["watch:tmpl"] = watchTemplates

// epidoc editor
function epidocEditor () {
    return src("node_modules/jinn-codemirror/dist/*")
        .pipe(dest("build/resources/scripts"))
}

// datalist-ajax
function datalistAjax () {
    return src("node_modules/datalist-ajax/dist/datalist-ajax.min.js")
        .pipe(dest("build/resources/scripts/datalist-ajax/datalist-ajax.min.js"))
}

// leaflet styles and images
function lfStyles () {
    return src("node_modules/leaflet/dist/leaflet.css")
        .pipe(dest("build/resources/css/leaflet/leaflet.css"))
}
function lfImages () {
    return src("node_modules/leaflet/dist/images")
        .pipe(dest("build/resources/images/leaflet"))
}

// OSD + images
function osdLib () {
    return src("node_modules/openseadragon/build/openseadragon/openseadragon.min.js")
        .pipe(dest("build/resources/lib"))
}
function osdImages () {
    return src("node_modules/openseadragon/build/openseadragon/images")
        .pipe(dest("build/resources/images/openseadragon"))
}

// prismjs themes
function prismThemes () {
    return src("node_modules/prismjs/themes")
        .pipe(dest("build/resources/css/prismjs"))
}

// pb-components
function pbComponents () {
    return src("node_modules/@teipublisher/pb-components/i18n/common")
        .pipe(dest("build/resources/i18n/common"))
}
const copyModules = parallel(
    epidocEditor, datalistAjax,
    lfStyles, lfImages, pbComponents, 
    prismThemes, osdImages, osdLib
)
exports["copy:modules"] = copyModules

/**
 * copy styles
 */
function styles () {
    return src('src/resources/css/*.css')
        .pipe(dest('build/resources/css'));
}
exports.styles = styles

function watchStyles () {
    watch('src/resources/css/*.css', series(styles))
}
exports["watch:styles"] = watchStyles

/**
 * minify EcmaSript files and put them into 'build/app/js'
 */
function minifyEs () {
    return src('src/resources/scripts/**/*.js')
        // .pipe(uglify())
        .pipe(dest('build/resources/scripts'))
}
exports.minify = minifyEs

function watchEs () {
    watch('src/resources/scripts/**/*.js', series(minifyEs))
}
exports["watch:es"] = watchEs

const static = 'src/**/*.{xml,html,xq,xquery,xql,xqm,xsl,xconf,json,svg,js,map,png,ico,woff,eot,ttf,odd}'

/**
 * copy html templates, XSL stylesheet, XMLs and XQueries to 'build'
 */
function copyStatic () {
    return src(static).pipe(dest('build'))
}
exports.copy = copyStatic

function watchStatic () {
    watch(static, series(copyStatic));
}
exports["watch:static"] = watchStatic

/**
 * Upload all files in the build folder to existdb.
 * This function will only upload what was changed
 * since the last run (see gulp documentation for lastRun).
 */
function deploy () {
    return src('build/**/*', {
        base: 'build',
        since: lastRun(deploy)
    })
        .pipe(existClient.dest({ target }))
}

function watchBuild () {
    watch('build/**/*', series(deploy))
}

// construct the current xar name from available data
const packageName = () => `${package.target}-${pkg.version}.xar`

/**
 * create XAR package in repo root
 */
function createXar () {
    return src('build/**/*', {base: 'build'})
        .pipe(zip(packageName()))
        .pipe(dest('./dist'))
}

/**
 * upload and install the latest built XAR
 */
function installXar () {
    return src('dist/' + packageName())
        .pipe(existClient.install({ packageUri }))
}

// composed tasks
const build = series(
    clean,
    styles,
    minifyEs,
    templates,
    copyStatic,
    copyModules
)
const watchAll = parallel(
    watchStyles,
    watchEs,
    watchStatic,
    watchTemplates,
    watchBuild
)

exports.build = build
exports.watch = watchAll

exports.deploy = series(build, deploy)
exports.xar = series(build, createXar)
exports.install = series(build, createXar, installXar)

// main task for day to day development
exports.default = series(build, deploy, watchAll)
