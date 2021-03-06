define [
    'leaflet',
    'proj4leaflet',
    'underscore',
    'app/base',
], (
    leaflet,
    p4j,
    _,
    sm
) ->

    RETINA_MODE = window.devicePixelRatio > 1

    getMaxBounds = (layer) ->
        L.latLngBounds L.latLng(59.5, 24.2), L.latLng(60.5, 25.5)

    wmtsPath = (style, language) ->
        stylePath =
            if style == 'accessible_map'
                if language == 'sv'
                    "osm-sm-visual-sv/etrs_tm35fin"
                else
                    "osm-sm-visual/etrs_tm35fin"
            else if RETINA_MODE
                if language == 'sv'
                    "osm-sm-sv-hq/etrs_tm35fin_hq"
                else
                    "osm-sm-hq/etrs_tm35fin_hq"
            else
                if language == 'sv'
                    "osm-sm-sv/etrs_tm35fin"
                else
                    "osm-sm/etrs_tm35fin"
        path = [
            "http://geoserver.hel.fi/mapproxy/wmts",
            stylePath,
            "{z}/{x}/{y}.png"
        ]
        path.join '/'

    makeLayer =
        tm35:
            crs: ->
                crsName = 'EPSG:3067'
                projDef = '+proj=utm +zone=35 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs'
                bounds = L.bounds L.point(-548576, 6291456), L.point(1548576, 8388608)
                originNw = [bounds.min.x, bounds.max.y]
                crsOpts =
                    resolutions: [8192, 4096, 2048, 1024, 512, 256, 128, 64, 32, 16, 8, 4, 2, 1, 0.5, 0.25, 0.125]
                    bounds: bounds
                    transformation: new L.Transformation 1, -originNw[0], -1, originNw[1]
                new L.Proj.CRS crsName, projDef, crsOpts

            layer: (opts) ->
                L.tileLayer wmtsPath(opts.style, opts.language),
                    maxZoom: 15
                    minZoom: 6
                    continuousWorld: true
                    tms: false

        gk25:
            crs: ->
                crsName = 'EPSG:3879'
                projDef = '+proj=tmerc +lat_0=0 +lon_0=25 +k=1 +x_0=25500000 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs'

                bounds = [25440000, 6630000, 25571072, 6761072]
                new L.Proj.CRS.TMS crsName, projDef, bounds,
                    resolutions: [256, 128, 64, 32, 16, 8, 4, 2, 1, 0.5, 0.25, 0.125, 0.0625, 0.03125]

            layer: (opts) ->
                geoserverUrl = (layerName, layerFmt) ->
                    "http://geoserver.hel.fi/geoserver/gwc/service/tms/1.0.0/#{layerName}@ETRS-GK25@#{layerFmt}/{z}/{x}/{y}.#{layerFmt}"
                if opts.style == 'ortographic'
                    new L.Proj.TileLayer.TMS geoserverUrl("hel:orto2013", "jpg"), opts.crs,
                        maxZoom: 12
                        minZoom: 2
                        continuousWorld: true
                        tms: false
                else
                    guideMapUrl = geoserverUrl("hel:Karttasarja", "gif")
                    guideMapOptions =
                        maxZoom: 12
                        minZoom: 2
                        continuousWorld: true
                        tms: false
                    (new L.Proj.TileLayer.TMS guideMapUrl, opts.crs, guideMapOptions).setOpacity 0.8

    SMap = L.Map.extend
        refitAndAddLayer: (layer) ->
            @mapState.adaptToLayer layer
            @addLayer layer
        refitAndAddMarker: (marker) ->
            @mapState.adaptToLatLngs [marker.getLatLng()]
            @addLayer marker
        adaptToLatLngs: (latLngs) ->
            @mapState.adaptToLatLngs latLngs
        adapt: ->
            @mapState.adaptToBounds null

    class MapMaker
        @makeBackgroundLayer: (options) ->
            coordinateSystem = switch options.style
                when 'guidemap' then 'gk25'
                when 'ortographic' then 'gk25'
                else 'tm35'
            layerMaker = makeLayer[coordinateSystem]
            crs = layerMaker.crs()
            options.crs = crs
            tileLayer = layerMaker.layer options
            tileLayer.on 'tileload', (e) =>
                e.tile.setAttribute 'alt', ''
            layer: tileLayer
            crs: crs
        @createMap: (domElement, options, mapOptions, mapState) ->
            {layer: layer, crs: crs} = MapMaker.makeBackgroundLayer options
            defaultMapOptions =
                crs: crs
                continuusWorld: true
                worldCopyJump: false
                zoomControl: false
                closePopupOnClick: false
                maxBounds: getMaxBounds options.style
                layers: [layer]
            _.extend defaultMapOptions, mapOptions
            map = new SMap domElement, defaultMapOptions
            mapState?.setMap map
            map.crs = crs
            map._baseLayer = layer
            map

    class MapUtils
        @createPositionMarker: (latLng, accuracy, type) ->
            Z_INDEX = -1000
            switch type
                when 'detected'
                    opts =
                        icon: L.divIcon
                            iconSize: L.point 40, 40
                            iconAnchor: L.point 20, 39
                            className: 'servicemap-div-icon'
                            html: '<span class="icon-icon-you-are-here"></span'
                        zIndexOffset: Z_INDEX
                    marker = L.marker latLng, opts
                when 'clicked'
                    marker = L.circleMarker latLng,
                        color: '#666'
                        weight: 2
                        opacity: 1
                        fill: false
                        clickable: false
                        zIndexOffset: Z_INDEX
                    marker.setRadius 6
                when 'address'
                    opts =
                        zIndexOffset: Z_INDEX
                        icon: L.divIcon
                            iconSize: L.point 40, 40
                            iconAnchor: L.point 20, 39
                            className: 'servicemap-div-icon'
                            html: '<span class="icon-icon-address"></span'
                    marker = L.marker latLng, opts
            return marker

        @overlappingBoundingBoxes: (map) ->
            crs = map.crs
            if map._originalGetBounds?
                latLngBounds = map._originalGetBounds()
            else
                latLngBounds = map.getBounds()
            METER_GRID = 1000
            DEBUG_GRID = false
            ne = crs.project latLngBounds.getNorthEast()
            sw = crs.project latLngBounds.getSouthWest()
            min = x: ne.x, y: sw.y
            max = y: ne.y, x: sw.x

            snapToGrid = (coord) ->
                parseInt(coord / METER_GRID) * METER_GRID
            coordinates = {}
            for dim in ['x', 'y']
                coordinates[dim] = coordinates[dim] or {}
                for value in [min[dim] .. max[dim]]
                    coordinates[dim][parseInt(snapToGrid(value))] = true

            pairs = _.flatten(
                [parseInt(x), parseInt(y)] for x in _.keys(coordinates.x) for y in _.keys(coordinates.y),
                true)

            bboxes = _.map pairs, ([x, y]) -> [[x, y], [x + METER_GRID, y + METER_GRID]]
            if DEBUG_GRID
                @debugGrid.clearLayers()
                for bbox in bboxes
                    sw = crs.projection.unproject(L.point(bbox[0]...))
                    ne = crs.projection.unproject(L.point(bbox[1]...))
                    sws = [sw.lat, sw.lng].join()
                    nes = [ne.lat, ne.lng].join()
                    unless @debugCircles[sws]
                        @debugGrid.addLayer L.circle(sw, 10)
                        @debugCircles[sws] = true
                    unless @debugCircles[nes]
                        @debugGrid.addLayer L.circle(ne, 10)
                        @debugCircles[nes] = true
                    # rect = L.rectangle([sw, ne])
                    # @debugGrid.addLayer rect
            bboxes

        @latLngFromGeojson: (object) ->
            L.latLng object?.get('location')?.coordinates?.slice(0).reverse()

        @getZoomlevelToShowAllMarkers: ->
            layer = p13n.get('map_background_layer')
            if layer == 'guidemap'
                return 8
            else if layer == 'ortographic'
                return 8
            else
                return 14

    makeDistanceComparator = (p13n) =>
        createFrom = (position) =>
            (obj) =>
                [a, b] = [MapUtils.latLngFromGeojson(position), MapUtils.latLngFromGeojson(obj)]
                result = a.distanceTo b
                result
        position = p13n.getLastPosition()
        if position?
            createFrom position

    MapMaker: MapMaker
    MapUtils: MapUtils
    makeDistanceComparator: makeDistanceComparator
