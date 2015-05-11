define [
    'moment',
    'underscore',
    'backbone',
    'i18next',
    'app/base',
    'app/settings',
    'app/spinner',
    'app/alphabet',
    'app/accessibility'
], (
    moment,
    _,
    Backbone,
    i18n,
    mixOf: mixOf,
    settings,
    SMSpinner,
    alphabet,
    accessibility
) ->

    BACKEND_BASE = appSettings.service_map_backend
    LINKEDEVENTS_BASE = appSettings.linkedevents_backend
    GEOCODER_BASE = appSettings.geocoder_url

    # TODO: remove and handle in geocoder
    MUNICIPALITIES =
        49: 'espoo'
        91: 'helsinki'
        92: 'vantaa'
        235: 'kauniainen'
    MUNICIPALITY_IDS = _.invert MUNICIPALITIES

    Backbone.ajax = (request) ->
        request = settings.applyAjaxDefaults request
        return Backbone.$.ajax.call Backbone.$, request

    class RESTFrameworkCollection extends Backbone.Collection
        parse: (resp, options) ->
            # Transform Django REST Framework response into PageableCollection
            # compatible structure.
            @fetchState =
                count: resp.count
                next: resp.next
                previous: resp.previous
            super resp.results, options

    class WrappedModel extends Backbone.Model
        initialize: (model) ->
            super()
            @wrap model
        wrap: (model) ->
            @set 'value', model or null
        value: ->
            @get 'value'
        isEmpty: ->
            return not @has 'value'
        isSet: ->
            return not @isEmpty()

    class GeoModel
        getLatLng: ->
            if @latLng?
                @latLng
            coords = @get('location')?.coordinates
            if coords?
                @latLng = L.GeoJSON.coordsToLatLng coords
            else
                null

        getDistanceToLastPosition: ->
            position = p13n.getLastPosition()
            if position?
                latLng = @getLatLng()
                if latLng?
                    position.getLatLng().distanceTo latLng
                else
                    null

    class SMModel extends Backbone.Model
        # FIXME/THINKME: Should we take care of translation only in
        # the view level? Probably.
        getText: (attr) ->
            val = @get attr
            if attr in @translatedAttrs
                return p13n.getTranslatedAttr val
            return val
        toJSON: (options) ->
            data = super()
            if not @translatedAttrs
                return data
            for attr in @translatedAttrs
                if attr not of data
                    continue
                data[attr] = p13n.getTranslatedAttr data[attr]
            return data

        url: ->
            ret = super
            if ret.substr -1 != '/'
                ret = ret + '/'
            return ret

        urlRoot: ->
            return "#{BACKEND_BASE}/#{@resourceName}/"

    class SMCollection extends RESTFrameworkCollection
        initialize: (models, options) ->
            @filters = {}
            @currentPage = 1
            if options?
                @pageSize = options.pageSize || 25

        getComparisonKey: (unit) ->
            p13n.getTranslatedAttr unit.get('name')

        url: ->
            obj = new @model
            return "#{BACKEND_BASE}/#{obj.resourceName}/"

        isSet: ->
            return not @isEmpty()

        setFilter: (key, val) ->
            if not val
                if key of @filters
                    delete @filters[key]
            else
                @filters[key] = val
            return @

        clearFilters: ->
            @filters = {}

        fetchNext: (options) ->
            if @fetchState? and not @fetchState.next
                return false

            @currentPage++
            defaults = {reset: false, remove: false}
            if options?
                options = _.extend options, defaults
            else
                options = defaults
            @fetch options

        fetch: (options) ->
            if options?
                options = _.clone options
            else
                options = {}

            data = _.clone @filters
            data.page = @currentPage
            data.page_size = @pageSize

            if options.data?
                data = _.extend data, options.data
            options.data = data

            if options.spinnerOptions?.container
                spinner = new SMSpinner(options.spinnerOptions)
                spinner.start()

                success = options.success
                error = options.error

                options.success = (collection, response, options) ->
                    spinner.stop()
                    success?(collection, response, options)

                options.error = (collection, response, options) ->
                    spinner.stop()
                    error?(collection, response, options)

            delete options.spinnerOptions

            super options

        fetchFields: (start, end, fields) ->
            # Fetches more model details for a specified range
            # in the collection.
            if not fields
                return $.Deferred().resolve().promise()
            filtered = _(@slice(start, end)).filter (m) =>
                for field in fields
                    if m.get(field) == undefined
                        return true
                return false
            idsToFetch = _.pluck filtered, 'id'
            unless idsToFetch.length
                return $.Deferred().resolve().promise()
            @fetch
                remove: false
                data:
                    page_size: idsToFetch.length
                    id: idsToFetch.join ','
                    include: fields.join ','

        comparatorKeys: ['default', 'alphabetic', 'alphabetic_reverse']
        getComparator: (key, direction) =>
            switch key
                when 'alphabetic'
                    alphabet.makeComparator direction
                when 'alphabetic_reverse'
                    alphabet.makeComparator -1
                when 'distance'
                    (x) => x.getDistanceToLastPosition()
                when 'default'
                    (x) => -x.get 'score'
                when 'accessibility'
                    (x) => x.getShortcomingCount()
                else
                    null
        comparatorWrapper: (fn) =>
            unless fn
                return fn
            if fn.length == 2
                (a, b) =>
                    fn @getComparisonKey(a), @getComparisonKey(b)
            else
                fn

        setComparator: (key, direction) ->
            @currentComparator = @comparatorKeys.indexOf(key)
            @comparator = @comparatorWrapper @getComparator(key, direction)
        cycleComparator: ->
            unless @currentComparator?
                @currentComparator = 0
            @currentComparator += 1
            @currentComparator %= @comparatorKeys.length
            @reSort @comparatorKeys[@currentComparator]
        reSort: (key, direction) ->
            @setComparator key, direction
            if @comparator?
                @sort()
            key
        getComparatorKey: ->
            @comparatorKeys[@currentComparator || 0]

    class Unit extends mixOf SMModel, GeoModel
        resourceName: 'unit'
        translatedAttrs: ['name', 'description', 'street_address']

        initialize: (options) ->
            super options
            @eventList = new EventList()

        getEvents: (filters, options) ->
            if not filters?
                filters = {}
            if 'start' not of filters
                filters.start = 'today'
            if 'sort' not of filters
                filters.sort = 'start_time'
            filters.location = "tprek:#{@get 'id'}"
            @eventList.filters = filters
            if not options?
                options =
                    reset: true
            else if not options.reset
                options.reset = true
            @eventList.fetch options

        isDetectedLocation: ->
            false
        isPending: ->
            false

        otpSerializeLocation: (opts) ->
            if opts.forceCoordinates
                coords = @get('location').coordinates
                "#{coords[1]},#{coords[0]}"
            else
                "poi:tprek:#{@get 'id'}"

        getSpecifierText: ->
            specifierText = ''
            level = null
            for service in @get 'services'
                if not level or service.level < level
                    specifierText = service.name[p13n.getLanguage()]
                    level = service.level
            return specifierText

        toJSON: (options) ->
            data = super()
            openingHours = _.filter @get('connections'), (c) ->
                c.section == 'opening_hours' and p13n.getLanguage() of c.name
            lang = p13n.getLanguage()
            if openingHours.length > 0
                data.opening_hours = _(openingHours)
                    .chain()
                    .sortBy 'type'
                    .map (hours) =>
                        content: hours.name[lang]
                        url: hours.www_url?[lang]
                    .value()

            highlights = _.filter @get('connections'), (c) ->
                c.section == 'miscellaneous' and p13n.getLanguage() of c.name
            data.highlights = _.sortBy highlights, (c) -> c.type

            links = _.filter @get('connections'), (c) ->
                c.section == 'links' and p13n.getLanguage() of c.name
            data.links = _.sortBy links, (c) -> c.type
            data

        hasBboxFilter: ->
            @collection?.filters?.bbox?

        hasAccessibilityData: ->
            @get('accessibility_properties')?.length

        getTranslatedShortcomings: ->
            profiles = p13n.getAccessibilityProfileIds()
            {status: status, results: shortcomings} = accessibility.getTranslatedShortcomings profiles, @

        getShortcomingCount: ->
            unless @hasAccessibilityData()
                return 10000
            shortcomings = @getTranslatedShortcomings()
            @shortcomingCount = 0
            for __, group of shortcomings
                @shortcomingCount += _.values(group).length
            @shortcomingCount

    class UnitList extends SMCollection
        model: Unit
        comparator: null
        comparatorKeys: ['default', 'accessibility', 'distance', 'alphabetic', 'alphabetic_reverse']

    class Department extends SMModel
        resourceName: 'department'
        translatedAttrs: ['name']

    class DepartmentList extends SMCollection
        model: Department

    class Organization extends SMModel
        resourceName: 'organization'
        translatedAttrs: ['name']

    class OrganizationList extends SMCollection
        model: Organization

    class AdministrativeDivision extends SMModel
        resourceName: 'administrative_division'
        translatedAttrs: ['name']

    class AdministrativeDivisionList extends SMCollection
        model: AdministrativeDivision

    class AdministrativeDivisionType extends SMModel
        resourceName: 'administrative_division_type'

    class AdministrativeDivisionTypeList extends SMCollection
        model: AdministrativeDivision

    class Service extends SMModel
        resourceName: 'service'
        translatedAttrs: ['name']
        initialize: ->
            @set 'units', new models.UnitList()

        getSpecifierText: ->
            specifierText = ''
            for ancestor, index in @get 'ancestors'
                if index > 0
                    specifierText += ' • '
                specifierText += ancestor.name[p13n.getLanguage()]
            return specifierText

    class Position extends mixOf Backbone.Model, GeoModel
        resourceName: 'address'
        origin: -> 'clicked'
        isPending: ->
            false
        urlRoot: ->
            "#{GEOCODER_BASE}/#{@resourceName}"
        isDetectedLocation: ->
            false
        isReverseGeocoded: ->
            @get('municipality')? and @get('street')?
        slugifyAddress: ->
            SEPARATOR = '-'
            municipalityId = @get('municipality').split('/', 5).pop()

            slug = []
            add = (x) -> slug.push x

            add @get('street').toLowerCase().replace(/\ /g, SEPARATOR)
            add @get('number')

            numberEnd = @get 'number_end'
            letter = @get 'letter'
            if numberEnd then add "#{SEPARATOR}#{numberEnd}"
            if letter then slug[slug.length-1] += SEPARATOR + letter
            @slug = "#{MUNICIPALITIES[municipalityId]}/#{slug.join(SEPARATOR)}"
            @slug

    class CoordinatePosition extends Position
        origin: ->
            if @isDetectedLocation()
                'detected'
            else
                super()
        initialize: (attrs) ->
            @isDetected = if attrs?.isDetected? then attrs.isDetected else false
        otpSerializeLocation: (opts) ->
            coords = @get('location').coordinates
            "#{coords[1]},#{coords[0]}"
        isDetectedLocation: ->
            @isDetected
        isPending: ->
            !@get('location')?

    class AddressPosition extends Position
        origin: -> 'address'
        initialize: (data) ->
            unless data?
                return
            super
            @set 'location',
                coordinates: data.location.coordinates
                type: 'Point'
        isDetectedLocation: ->
            false
        otpSerializeLocation: (opts) ->
            coords = @get('location')['coordinates']
            coords[1] + "," + coords[0]

    class PositionList extends Backbone.Collection
        resourceName: 'address'
        @fromPosition: (position) ->
            instance = new PositionList()
            name = position.get 'name'
            location = position.get 'location'
            if location and not name
                instance.model = AddressPosition
                instance.fetch data:
                    lat: location.coordinates[1]
                    lon: location.coordinates[0]
            else if name and not location
                instance.model = AddressPosition
                opts = name: name
                municipality = position.get 'municipality'
                if municipality
                    opts.municipality = municipality
                instance.fetch data: opts

            instance

        @fromSlug: (slug) ->
            SEPARATOR = /-/g
            [municipality, address] = slug.split '/'
            startOfNumber = address.search /[0-9]/
            street = address[0 .. startOfNumber - 2].replace SEPARATOR, ' '
            numberPart = address[startOfNumber .. address.length].replace SEPARATOR, ' '
            name = "#{street} #{numberPart}"
            municipalityId = MUNICIPALITY_IDS[municipality]
            @fromPosition new Position
                name: name
                municipality: municipalityId
        parse: (resp, options) ->
            super resp.objects, options
        url: ->
            "#{GEOCODER_BASE}/#{@resourceName}/"

    class RoutingParameters extends Backbone.Model
        initialize: (attributes)->
            @set 'endpoints', attributes?.endpoints.slice(0) or [null, null]
            @set 'origin_index', attributes?.origin_index or 0
            @set 'time_mode', attributes?.time_mode or 'depart'
            @listenTo @, 'change:time_mode', -> @triggerComplete()

        swapEndpoints: (opts)->
            @set 'origin_index', @_getDestinationIndex()
            unless opts?.silent
                @trigger 'change'
                @triggerComplete()
        setOrigin: (object, opts) ->
            index = @get 'origin_index'
            @get('endpoints')[index] = object
            @trigger 'change'
            unless opts?.silent
                @triggerComplete()
        setDestination: (object) ->
            @get('endpoints')[@_getDestinationIndex()] = object
            @trigger 'change'
            @triggerComplete()
        getDestination: ->
            @get('endpoints')[@_getDestinationIndex()]
        getOrigin: ->
            @get('endpoints')[@_getOriginIndex()]
        getEndpointName: (object) ->
            if not object?
                return ''
            else if object.isDetectedLocation()
                if object.isPending()
                    return i18n.t('transit.location_pending')
                else
                    return i18n.t('transit.current_location')
            else if object instanceof CoordinatePosition
                return i18n.t('transit.user_picked_location')
            else if object instanceof Unit
                return object.getText('name')
            else if object instanceof AddressPosition
                return object.get('name')
        getEndpointLocking: (object) ->
            return object instanceof models.Unit
        isComplete: ->
            for endpoint in @get 'endpoints'
                unless endpoint? then return false
                if endpoint instanceof Position
                    if endpoint.isPending()
                        return false
            true
        ensureUnitDestination: ->
            if @getOrigin() instanceof Unit
                @swapEndpoints
                    silent: true
        triggerComplete: ->
            if @isComplete()
                @trigger 'complete'
        setTime: (time, opts) ->
            datetime = @getDatetime()
            mt = moment(time)
            m = moment(datetime)
            m.hours mt.hours()
            m.minutes mt.minutes()
            datetime = m.toDate()
            @set 'time', datetime, opts
            @triggerComplete()
        setDate: (date, opts) ->
            datetime = @getDatetime()
            md = moment(date)
            datetime.setDate md.date()
            datetime.setMonth md.month()
            datetime.setYear md.year()
            @set 'time', datetime, opts
            @triggerComplete()
        setTimeAndDate: (date) ->
            @setTime(date)
            @setDate(date)
        setDefaultDatetime: ->
            @set 'time', @getDefaultDatetime()
            @triggerComplete()
        clearTime: ->
            @set 'time', null
        getDefaultDatetime: (currentDatetime) ->
            time = moment new Date()
            mode = @get 'time_mode'
            if mode == 'depart'
                return time.toDate()
            time.add 60, 'minutes'
            minutes = time.minutes()
            # Round upwards to nearest 10 min
            time.minutes (minutes - minutes % 10 + 10)
            time.toDate()
        getDatetime: ->
            time = @get('time')
            unless time?
                time = @getDefaultDatetime()
            time

        isTimeSet: ->
            @get('time')?
        setTimeMode: (timeMode) ->
            @set 'time_mode', timeMode
            @triggerComplete()

        _getOriginIndex: ->
            @get 'origin_index'
        _getDestinationIndex: ->
            (@_getOriginIndex() + 1) % 2

    class Language extends Backbone.Model

    class LanguageList extends Backbone.Collection
        model: Language

    class ServiceList extends SMCollection
        model: Service
        initialize: ->
            super
            @chosenService = null
        expand: (id, spinnerOptions = {}) ->
            if not id
                @chosenService = null
                @fetch
                    data:
                        level: 0
                    spinnerOptions: spinnerOptions
                    success: =>
                        @trigger 'finished'
            else
                @chosenService = new Service(id: id)
                @chosenService.fetch
                    success: =>
                        @fetch
                            data:
                                parent: id
                            spinnerOptions: spinnerOptions
                            success: =>
                                @trigger 'finished'

    class SearchList extends SMCollection
        model: (attrs, options) ->
                typeToModel =
                    service: Service
                    unit: Unit

                type = attrs.object_type
                if type of typeToModel
                    return new typeToModel[type](attrs, options)
                else
                    console.log "Unknown search result type '#{type}', #{attrs.object_type}", attrs
                    return new Backbone.Model(attrs, options)

        search: (query, options) ->
            @currentPage = 1
            @query = query
            opts = _.extend {}, options
            opts.data =
                q: query
                language: p13n.getLanguage()
                only: 'name,location,root_services'
            city = p13n.get('city')
            if city
                opts.data.municipality = city
            @fetch opts
            opts

        url: ->
            return "#{BACKEND_BASE}/search/"

    class LinkedEventsModel extends SMModel
        urlRoot: ->
            return "#{LINKEDEVENTS_BASE}/#{@resourceName}/"

    class LinkedEventsCollection extends SMCollection
        url: ->
            obj = new @model
            return "#{LINKEDEVENTS_BASE}/#{obj.resourceName}/"

        parse: (resp, options) ->
            @fetchState =
                count: resp.meta.count
                next: resp.meta.next
                previous: resp.meta.previous
            RESTFrameworkCollection.__super__.parse.call @, resp.data, options


    class Event extends LinkedEventsModel
        resourceName: 'event'
        translatedAttrs: ['name', 'info_url', 'description', 'short_description',
                           'location_extra_info']
        toJSON: (options) ->
            data = super()
            data.links = _.filter @get('external_links'), (link) ->
                link.language == p13n.getLanguage()
            data

        getUnit: () ->
            unitId = @get('location')['@id'].match(/^.*tprek%3A(\d+)/)
            unless unitId?
                return null
            return new models.Unit id: unitId[1]


    class EventList extends LinkedEventsCollection
        model: Event


    exports =
        Unit: Unit
        Service: Service
        UnitList: UnitList
        Department: Department
        DepartmentList: DepartmentList
        Organization: Organization
        OrganizationList: OrganizationList
        ServiceList: ServiceList
        AdministrativeDivision: AdministrativeDivision
        AdministrativeDivisionList: AdministrativeDivisionList
        AdministrativeDivisionType: AdministrativeDivisionType
        AdministrativeDivisionTypeList: AdministrativeDivisionTypeList
        SearchList: SearchList
        Language: Language
        LanguageList: LanguageList
        Event: Event
        WrappedModel: WrappedModel
        EventList: EventList
        RoutingParameters: RoutingParameters
        Position: Position
        CoordinatePosition: CoordinatePosition
        AddressPosition: AddressPosition
        PositionList: PositionList

    # Expose models to browser console to aid in debugging
    window.models = exports

    return exports
