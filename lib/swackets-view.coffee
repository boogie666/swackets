{Range, Point, CompositeDisposable} = require 'atom'

module.exports =
class SwacketsView

    intervalID = null
    openBrackets = 0
    config = {}
    totalColors = 11
    stylesheet = null

    constructor: ->
        config = @config()
        @applyStylesheet()
        @sweatifyTimeout()

        @subscriptions = new CompositeDisposable
        @subscriptions.add atom.workspace.onDidChangeActivePaneItem =>
            config = @config()
            @applyStylesheet()
            @sweatifyTimeout()
            editor = atom.workspace.getActiveTextEditor()
            return unless editor
            @subscriptions.add editor.onDidChange(@sweatifyTimeout)

        intervalID = setInterval @sweatifyTimeout, 140 #onScroll better in some cases, worse when scrolling

        editor = atom.workspace.getActiveTextEditor()
        return unless editor
        @subscriptions.add editor.onDidChange(@sweatifyTimeout)

    destroy: ->
        clearInterval(intervalID)
        @subscriptions.dispose()

    config: ->
        open = []
        close = []

        if (atom.config.get('swackets.colorBrackets'))
          open.push '{'
          close.push '}'

        if (atom.config.get('swackets.colorParens'))
          open.push '('
          close.push ')'

        if (atom.config.get('swackets.colorSquareBrackets'))
          open.push '['
          close.push ']'

        openExpr = ('\\' + s for s in open).join('')
        closeExpr = ('\\' + s for s in close).join('')
        expr = openExpr + closeExpr

        return {
          openSyntax: open,
          closeSyntax: close,
          regex: new RegExp('^.*?([' + expr + ']+)$'),
          openRegex: new RegExp('[' + openExpr + ']', 'g'),
          closeRegex: new RegExp('[' + closeExpr + ']', 'g')
        }

    getSwacketsStylesheet: ->
        if !stylesheet
          stylesheet = document.createElement('style')
          stylesheet.id = 'swackets-custom-style'
          stylesheet.appendChild document.createTextNode('')
          document.head.appendChild stylesheet
        stylesheet.sheet

    applyStylesheet: ->
        sheet = @getSwacketsStylesheet()
        colors = atom.config.get('swackets.colors')
        totalColors = colors.length - 1
        for rule in sheet.cssRules
          sheet.deleteRule(0)
        for color, index in colors
          sheet.insertRule("atom-text-editor .swackets-#{index} {color: #{color}}", 0)

    sweatifyTimeout: =>
        setTimeout @sweatify, 16

    sweatify: =>
        lines = document.querySelector('atom-text-editor.is-focused .lines')
        return if !lines
        lines.style.display = 'none'

        lineGroups = @lineGroupsQueryToArray document.querySelectorAll('atom-text-editor.is-focused .lines > div:not(.cursors) > div:not(.icon-right)')
        @sweatifyLineGroups(lineGroups)

        lines.style.display = ''

    lineGroupsQueryToArray: (query) ->
        arr = []
        for item in query
            # Sometimes, Atom keeps one of the lineGroups with a single line children,
            # which we need to ignore. For example, when we scroll to the line 192, Atom
            # may still have a lineGroup with the greatest zIndex with only line 60.
            # This mess up our calculation for which line is the fist one on the screen so
            # we can calculate the initial openBracketsOffset
            continue if item.children.length == 2 and +item.children[1].dataset.screenRow > 0
            arr.push item
        arr

    sweatifyLineGroups: (lineGroups) ->
        sortedLineGroups = lineGroups.sort (a, b) =>
            Math.min(1, Math.max(-1, b.style.zIndex - a.style.zIndex))

        firstLine = sortedLineGroups[0].querySelector('.line')
        openBrackets = @openBracketsOffsetFor(+firstLine.dataset.screenRow)

        sortedLineGroups.forEach (lineGroup) =>
            spans = lineGroup.querySelectorAll('span:not(.comment)')
            @sweatifySpans(spans)

    openBracketsOffsetFor: (lineNumber) ->
        {openRegex, closeRegex} = config

        range = new Range(new Point(0, 0), new Point(lineNumber, 0))
        editor = atom.workspace.getActiveTextEditor()
        return 0 unless editor
        text = editor.getTextInBufferRange(range)

        openBracketsOffset = 0
        openBracketsOffset += text.match(openRegex)?.length || 0
        openBracketsOffset -= text.match(closeRegex)?.length || 0

        return Math.max(0, openBracketsOffset % (totalColors + 1))

    sweatifySpans: (spans) ->
        {regex, closeRegex} = config
        just_saw_fold_marker = false

        for span in spans
            match = span.innerHTML.match(regex)
            # here's where we check and revert the assumption made below
            if just_saw_fold_marker && match && match[0].match(closeRegex)
              just_saw_fold_marker = false
              openBrackets++;

            if match
              @sweatifySpan(span, match)

            # if we're not dealing with a code fold
            # we need to check if the current span is actually a fold
            # if so we just assume that the brace is closed within the fold
            # on the next iteration we check if the next token is a close bracket
            # and if it is we revert this assumption
            if !just_saw_fold_marker
              just_saw_fold_marker = span.classList.contains("fold-marker")
              if just_saw_fold_marker
                openBrackets--;

            continue

    sweatifySpan: (span, match) ->
        {openRegex, closeRegex} = config

        color = openBrackets
        if (match[0].match(openRegex)) and (! match[0].match(closeRegex))
            openBrackets++
            if openBrackets > totalColors
                openBrackets = 0
        else if (match[0].match(closeRegex)) and (! match[0].match(openRegex))
            openBrackets--
            if openBrackets < 0
                openBrackets = totalColors
            color = openBrackets
        className = ' swackets-' + color
        span.className = span.className.replace(/( swackets-\d+|$)/, className)
