angular.module('markever', ['ui.ace'])

angular.module('markever')
.controller 'EditorController', ['$scope','$window', '$http', '$sce', 'enmlRenderer', 'scrollSyncor'
($scope, $window, $http, $sce, enmlRenderer, scrollSyncor) ->
    # ------------------------------------------------------------------------------------------------------------------
    # define frequently-used jquery elements
    # ------------------------------------------------------------------------------------------------------------------
    $html_div = $('#md_html_div')

    # ------------------------------------------------------------------------------------------------------------------
    # ng related
    # ------------------------------------------------------------------------------------------------------------------
    vm = this
    vm.aceLoaded = (_editor) ->
        # reserve, do nothing at the moment
    vm.aceChanged = (e) ->
        # reserve, do nothing at the moment
    vm.md2Html = ->
        vm.html = $window.marked(vm.markdown)
        vm.htmlSafe = $sce.trustAsHtml(vm.html)

    # ------------------------------------------------------------------------------------------------------------------
    # sync scroll between two columns
    # refer: http://stackoverflow.com/questions/18952623/synchronized-scrolling-using-jquery
    # ------------------------------------------------------------------------------------------------------------------
    $scope.aceLoaded = (editor) =>
        scrollSyncor.syncScroll(editor, $html_div)

    $scope.aceChanged = (e) ->
        $html_div = $('#md_html_div')
        $html_div.find('pre code').each (i, block) ->
            hljs.highlightBlock(block)
        MathJax.Hub.Queue(['Typeset', MathJax.Hub, $html_div.get(0)])

    # ------------------------------------------------------------------------------------------------------------------
    # save note
    # ------------------------------------------------------------------------------------------------------------------
    vm.save_note = ->
        # fill the hidden html div
        html_div_hidden = $('#md_html_div_hidden')
        final_note_xml = enmlRenderer.getEnmlFromElement(html_div_hidden, vm.markdown)
        # set title to content of first H1 tag
        title = 'New Note - Markever'
        if html_div_hidden.find('h1').size() > 0
            title = html_div_hidden.find('h1').text()
        else if html_div_hidden.find('h2').size() > 0
            title = html_div_hidden.find('h2').text()
        else if html_div_hidden.find('h3').size() > 0
            title = html_div_hidden.find('h3').text()
        else if html_div_hidden.find('p').size() > 0
            title = html_div_hidden.find('p').text()
        # invoke the api
        $.post('/api/v1/notes', {title: title, contentXmlStr: final_note_xml})
            .done (data) ->
                alert('create note succeed: \n' + JSON.stringify(data))
            .fail (data) ->
                alert('create note failed: \n' + JSON.stringify(data))
]


# ----------------------------------------------------------------------------------------------------------------------
# Service: enmlRenderer
# ----------------------------------------------------------------------------------------------------------------------
angular.module('markever').factory 'enmlRenderer', ->
    getEnmlFromElement = (jq_element, markdown) ->
        # highlight code & style Latex
        jq_element.find('pre code').each (i, block) ->
            hljs.highlightBlock(block)
        MathJax.Hub.Queue(['Typeset', MathJax.Hub, jq_element.get(0)])

        # remove all script tags
        jq_element.find('script').remove()

        # add inline style
        # refer: https://github.com/Karl33to/jquery.inlineStyler
        # TODO still too much redundant styles
        inline_styler_option = {
            'propertyGroups' : {
                'font-matters' : ['font-size', 'font-family', 'font-style', 'font-weight'],
                'text-matters' : ['text-indent', 'text-align', 'text-transform', 'letter-spacing', 'word-spacing',
                                  'word-wrap', 'white-space', 'line-height', 'direction'],
                'display-matters' : ['display'],
                'size-matters' : ['width', 'height'],
                'color-matters' : ['color', 'background-color'],
                'position-matters' : ['margin', 'margin-left', 'margin-right', 'margin-top', 'margin-bottom',
                                      'padding', 'padding-left', 'padding-right', 'padding-top', 'padding-bottom',
                                      'float'],
                'border-matters' : ['border', 'border-left', 'border-right', 'border-radius',
                                    'border-top', 'border-right', 'border-color'],
            },
            'elementGroups' : {
                # N.B. UPPERCASE tags
                'font-matters' : ['DIV', 'BLOCKQUOTE', 'SPAN', 'STRONG', 'EM', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6'],
                'text-matters' : ['SPAN', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6'],
                'display-matters' : ['HR', 'PRE', 'SPAN', 'UL', 'OL', 'LI', 'PRE', 'CODE'],
                'size-matters' : ['HR', 'SPAN', 'UL', 'OL', 'LI'],
                'color-matters' : ['DIV', 'SPAN', 'PRE', 'CODE', 'BLOCKQUOTE'],
                'position-matters' : ['DIV', 'PRE', 'BLOCKQUOTE', 'SPAN', 'HR', 'UL', 'OL', 'LI', 'P',
                                      'H1', 'H2', 'H3', 'H4', 'H5', 'H6'],
                'border-matters' : ['HR', 'BLOCKQUOTE', 'SPAN', 'PRE', 'CODE'],
            }
        }
        jq_element.inlineStyler(inline_styler_option)

        # set href to start with 'http' is no protocol assigned
        jq_element.find('a').attr 'href', (i, href) ->
            if not href.toLowerCase().match('(^http)|(^https)|(^file)')
                return 'http://' + href
            else
                return href

        # clean the html tags/attributes
        html_clean_option = {
            format: true,
            allowedTags: ['a', 'abbr', 'acronym', 'address', 'area', 'b', 'bdo', 'big', 'blockquote',
                          'br', 'caption', 'center', 'cite', 'code', 'col', 'colgroup', 'dd', 'del',
                          'dfn', 'div', 'dl', 'dt', 'em', 'font', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
                          'hr', 'i', 'img', 'ins', 'kbd', 'li', 'map', 'ol', 'p', 'pre', 'q', 's',
                          'samp', 'small', 'span', 'strike', 'strong', 'sub', 'sup', 'table', 'tbody',
                          'td', 'tfoot', 'th', 'thead', 'title', 'tr', 'tt', 'u', 'ul', 'var', 'xmp',],
            allowedAttributes: [['href', ['a']], ['style']],
            removeAttrs: ['id', 'class', 'onclick', 'ondblclick', 'accesskey', 'data', 'dynsrc', 'tabindex',],
        }
        cleaned_html = $.htmlClean(jq_element.html(), html_clean_option);
        # FIXME hack for strange class attr not removed
        cleaned_html = cleaned_html.replace(/class='[^']*'/g, '')
        cleaned_html = cleaned_html.replace(/class="[^"]*"/g, '')

        # embbed raw markdown content into the html
        cleaned_html = cleaned_html +
            '<center style="display:none">' +
            $('<div />').text(markdown).html() +
            '</center>'

        # add XML header & wrap with <en-note></en-note>
        final_note_xml = '<?xml version="1.0" encoding="utf-8"?>' +
                         '<!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">' +
                         '<en-note>' +
                         cleaned_html +
                         '</en-note>'
        # FIXME debugging info
        console.log(final_note_xml)
        return final_note_xml

    return {
        getEnmlFromElement : getEnmlFromElement
    }


# ----------------------------------------------------------------------------------------------------------------------
# Service: enmlRenderer
# ----------------------------------------------------------------------------------------------------------------------
angular.module('markever').factory 'scrollSyncor', ->
    syncScroll = (ace_editor, jq_div) ->
        ace_editor.setShowPrintMargin(false)
        # sync scroll: md -> html
        editor_scroll_handler = (scroll) =>
            percentage = scroll / (ace_editor.session.getScreenLength() * \
                ace_editor.renderer.lineHeight - ($(ace_editor.renderer.getContainerElement()).height()))
            if percentage > 1 or percentage < 0 then return
            percentage = Math.floor(percentage * 1000) / 1000;
            # detach other's scroll handler first
            jq_div.off('scroll', html_scroll_handler)
            md_html_div = jq_div.get(0)
            md_html_div.scrollTop = percentage * (md_html_div.scrollHeight - md_html_div.offsetHeight)
            # re-attach other's scroll handler at the end, with some delay
            setTimeout (-> jq_div.scroll(html_scroll_handler)), 10
        ace_editor.session.on('changeScrollTop', editor_scroll_handler)

        # sync scroll: html -> md
        html_scroll_handler = (e) =>
            md_html_div = jq_div.get(0)
            percentage = md_html_div.scrollTop / (md_html_div.scrollHeight - md_html_div.offsetHeight)
            if percentage > 1 or percentage < 0 then return
            percentage = Math.floor(percentage * 1000) / 1000;
            # detach other's scroll handler first
            ace_editor.getSession().removeListener('changeScrollTop', editor_scroll_handler);
            ace_editor.session.setScrollTop((ace_editor.session.getScreenLength() * \
                ace_editor.renderer.lineHeight - $(ace_editor.renderer.getContainerElement()).height()) * percentage)
            # re-attach other's scroll handler at the end, with some delay
            setTimeout (-> ace_editor.session.on('changeScrollTop', editor_scroll_handler)), 20
        jq_div.scroll(html_scroll_handler)

    return {
        syncScroll : syncScroll
    }

