define [
    'underscore',
    'app/views/base',
    'app/views/accessibility-personalisation',
], (
    _,
    base,
    AccessibilityPersonalisationView
) ->

    class FeedbackFormView extends base.SMLayout
        template: 'feedback-form'
        className: 'content modal-dialog'
        regions:
            accessibility: '#accessibility-section'
        events:
            'submit': '_submit'
            'change input[type=checkbox]': '_onCheckboxChanged'
            'click .personalisations li': '_onPersonalisationClick'
            'blur input[type=text]': '_onFormInputBlur'
            'blur input[type=email]': '_onFormInputBlur'
            'blur textarea': '_onFormInputBlur'

        initialize: ({unit: @unit, model: @model}) ->
            @listenTo @model, 'change', =>
                console.log @model.toJSON()
        onRender: ->
            @_adaptInputWidths @$el, 'input[type=text]'
            @accessibility.show new AccessibilityPersonalisationView(@model.get('accessibility_viewpoints') or [])

        serializeData: ->
            keys = [
                'title', 'first_name', 'description',
                'email', 'accessibility_viewpoints'
            ]
            value = (key) => @model.get(key) or ''
            values = _.object keys, _(keys).map(value)
            values.accessibility_enabled = @model.get('accessibility_enabled') or false
            values.email_enabled = @model.get('email_enabled') or false
            values.unit = @unit.toJSON()
            values

        _adaptInputWidths: ($el, selector) ->
            _.defer =>
                $el.find(selector).each ->
                    pos = $(@).position().left
                    width = 440
                    width -= pos
                    $(@).css 'width', "#{width}px"
                $el.find('textarea').each -> $(@).css 'width', "460px"

        _submit: (ev) ->
            ev.preventDefault()
            @model.set 'unit', @unit
            @model.save()

        _onCheckboxChanged: (ev) ->
            target = ev.currentTarget
            checked = target.checked
            $hiddenSection = $(target).closest('.form-section').find('.hidden-section')
            if checked
                $hiddenSection.removeClass 'hidden'
                @_adaptInputWidths $hiddenSection, 'input[type=email]'
            else
                $hiddenSection.addClass 'hidden'
            @_setModelField @_getModelFieldId($(target)), checked

        _onFormInputBlur: (ev) ->
            $target = $ ev.currentTarget
            contents = $target.val()
            id = @_getModelFieldId $target
            @_setModelField id, contents

        _getModelFieldId: ($target) ->
            try
                $target.attr('id').replace /open311-/, ''
            catch TypeError
                null

        _setModelField: (id, val) ->
            @model.set id, val

        _onPersonalisationClick: (ev) ->
            $target = $(ev.currentTarget)
            type = $target.data 'type'
            $target.closest('#accessibility-section').find('li').removeClass 'selected'
            $target.addClass 'selected'
            @model.set 'accessibility_viewpoints', [type]
