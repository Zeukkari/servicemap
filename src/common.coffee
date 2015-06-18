require.config
    baseUrl: 'vendor'
    paths:
        app: '../app'
        embed: '../embed'
    shim:
        bootstrap:
            deps: ['jquery']
        backbone:
            deps: ['underscore', 'jquery']
            exports: 'Backbone'
        'typeahead.bundle':
            deps: ['jquery']
        TweenLite:
            deps: ['CSSPlugin', 'EasePack']
        'leaflet.markercluster':
            deps: ['leaflet']
        'leaflet.activearea':
            deps: ['leaflet']
        'bootstrap-datetimepicker':
            deps: ['bootstrap']
        'bootstrap-tour':
            deps: ['bootstrap']
        'iexhr':
            deps: ['jquery']
        'leaflet.snogylop':
            deps: ['leaflet']
    deps: [ 'require' ]
    callback: (require) ->
        'use strict'
        filename = location.pathname.match(/\/([^\/]*)$/)
        modulename = undefined
        if filename and filename[1] != ''
            modulename = [
                'app'
                filename[1].split('.')[0]
                'main'
            ].join('/')
            console.info "Module: ", modulename
            require [ modulename ]
        else
            if window.console
                console.log 'no modulename found via location.pathname'
        return
