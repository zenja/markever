$ ->
    ####################################################################################################################
    #                                                 DEFINE FUNCTIONS
    ####################################################################################################################

    update_html = (editor, $html_div_0) ->
        $html_div_0.html(marked(editor.getValue()))
        $html_div_0.find('pre code').each (i, block) ->
            hljs.highlightBlock(block)
        # render Latax
        MathJax.Hub.Queue(["Typeset", MathJax.Hub, $html_div_0.get(0)])


    ####################################################################################################################
    #                                                      MAIN
    ####################################################################################################################

    # ------------------------------------------------------------------------------------------------------------------
    # define frequently-used jquery elements
    # ------------------------------------------------------------------------------------------------------------------
    $html_div = $("#md_html_div")

    # ------------------------------------------------------------------------------------------------------------------
    # ace editor creation and conf
    # ------------------------------------------------------------------------------------------------------------------
    editor = ace.edit("md_editor_div");
    editor.renderer.setShowGutter(false);
    editor.setShowPrintMargin(false);
    editor.getSession().setMode("ace/mode/markdown");
    editor.getSession().setUseWrapMode(true);

    # ------------------------------------------------------------------------------------------------------------------
    # auto focus on editor upon startup
    # ------------------------------------------------------------------------------------------------------------------
    editor.focus();

    # ------------------------------------------------------------------------------------------------------------------
    # auto-generate html when editing markdown
    # ------------------------------------------------------------------------------------------------------------------
    editor.on "change", ->
        update_html(editor, $html_div)

    # ------------------------------------------------------------------------------------------------------------------
    # "show html" link for debugging
    # ------------------------------------------------------------------------------------------------------------------
    $("a#show_html").click ->
        alert(marked(editor.getValue()))

    # ------------------------------------------------------------------------------------------------------------------
    # "list" link for debugging: list all (not all actually...) Markever notes
    # ------------------------------------------------------------------------------------------------------------------
    $("a#get_all_notes").click ->
        $.get("/api/v1/notes")
            .done (data) ->
                alert("list all notes succeeded: \n" + JSON.stringify(data))
            .fail (data) ->
                alert("list all notes failed: \n" + JSON.stringify(data))

    # ------------------------------------------------------------------------------------------------------------------
    # "save note" link for debugging
    # ------------------------------------------------------------------------------------------------------------------
    $("a#save_note").click ->
        # fill the hidden html div
        $html_div_hidden = $("#md_html_div_hidden")
        update_html(editor, $html_div_hidden)

        # remove all script tags
        $html_div_hidden.find("script").remove()

        # add inline style
        # refer: https://github.com/Karl33to/jquery.inlineStyler
        # TODO still too much redundant styles
        inline_styler_option = {
            'propertyGroups' : {
                'font-matters' : ['font-size', 'font-family', 'font-style', 'font-weight'],
                'text-matters' : ['text-indent', 'text-align', 'text-transform', 'letter-spacing', 'word-spacing',
                                  'word-wrap', 'white-space', 'line-height', 'direction']
                'size-matters' : ['display', 'width', 'height'],
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
                'size-matters' : ['HR', 'PRE', 'SPAN', 'UL', 'OL', 'LI', 'PRE', 'CODE'],
                'color-matters' : ['DIV', 'SPAN', 'PRE', 'CODE', 'BLOCKQUOTE'],
                'position-matters' : ['DIV', 'PRE', 'BLOCKQUOTE', 'SPAN', 'HR', 'UL', 'OL', 'LI', 'P',
                                      'H1', 'H2', 'H3', 'H4', 'H5', 'H6'],
                'border-matters' : ['HR', 'BLOCKQUOTE', 'SPAN', 'PRE', 'CODE'],
            }
        }
        $html_div_hidden.inlineStyler(inline_styler_option)

        # set href to start with "http" is no protocol assigned
        $html_div_hidden.find("a").attr "href", (i, href) ->
            if not href.toLowerCase().match("(^http)|(^https)|(^file)")
                return "http://" + href
            else
                return href

        # clean the html tags/attributes
        html_clean_option = {
            format: true,
            allowedTags: ["a", "abbr", "acronym", "address", "area", "b", "bdo", "big", "blockquote",
                          "br", "caption", "center", "cite", "code", "col", "colgroup", "dd", "del",
                          "dfn", "div", "dl", "dt", "em", "font", "h1", "h2", "h3", "h4", "h5", "h6",
                          "hr", "i", "img", "ins", "kbd", "li", "map", "ol", "p", "pre", "q", "s",
                          "samp", "small", "span", "strike", "strong", "sub", "sup", "table", "tbody",
                          "td", "tfoot", "th", "thead", "title", "tr", "tt", "u", "ul", "var", "xmp",],
            allowedAttributes: [["href", ["a"]], ["style"]],
            removeAttrs: ["id", "class", "onclick", "ondblclick", "accesskey", "data", "dynsrc", "tabindex",],
        }
        cleaned_html = $.htmlClean($html_div_hidden.html(), html_clean_option);
        # FIXME hack for strange class attr not removed
        cleaned_html = cleaned_html.replace(/class="[^"]*"/g, "")

        # add XML header & wrap with <en-note></en-note>
        final_note_xml = "<?xml version='1.0' encoding='utf-8'?>" +
                         "<!DOCTYPE en-note SYSTEM 'http://xml.evernote.com/pub/enml2.dtd'>" +
                         "<en-note>" +
                         cleaned_html +
                         "</en-note>"
        console.log(final_note_xml)

        # set title to content of first H1 tag
        title = "New Note - Markever"
        if $html_div_hidden.find("h1").size() > 0
            title = $html_div_hidden.find("h1").text()
        else if $html_div_hidden.find("h2").size() > 0
            title = $html_div_hidden.find("h2").text()
        else if $html_div_hidden.find("h3").size() > 0
            title = $html_div_hidden.find("h3").text()
        else if $html_div_hidden.find("p").size() > 0
            title = $html_div_hidden.find("p").text()

        # invoke the api
        $.post("/api/v1/notes", {title: title, contentXmlStr: final_note_xml})
            .done (data) ->
                alert("create note succeed: \n" + JSON.stringify(data))
            .fail (data) ->
                alert("create note failed: \n" + JSON.stringify(data))

    # ------------------------------------------------------------------------------------------------------------------
    # sync scroll between two columns
    # refer: http://stackoverflow.com/questions/18952623/synchronized-scrolling-using-jquery
    # ------------------------------------------------------------------------------------------------------------------
    # sync scroll: md -> html
    editor_scroll_handler = (scroll) =>
        percentage = scroll / (editor.session.getScreenLength() * \
            editor.renderer.lineHeight - ($(editor.renderer.getContainerElement()).height()))
        if percentage > 1 or percentage < 0 then return
        percentage = Math.floor(percentage * 1000) / 1000;
        # detach other's scroll handler first
        $html_div.off('scroll', html_scroll_handler)
        md_html_div = $html_div.get(0)
        md_html_div.scrollTop = percentage * (md_html_div.scrollHeight - md_html_div.offsetHeight)
        # re-attach other's scroll handler at the end, with some delay
        setTimeout (-> $html_div.scroll(html_scroll_handler)), 10
    editor.session.on('changeScrollTop', editor_scroll_handler)

    # sync scroll: html -> md
    html_scroll_handler = (e) =>
        md_html_div = $html_div.get(0)
        percentage = md_html_div.scrollTop / (md_html_div.scrollHeight - md_html_div.offsetHeight)
        if percentage > 1 or percentage < 0 then return
        percentage = Math.floor(percentage * 1000) / 1000;
        # detach other's scroll handler first
        editor.getSession().removeListener('changeScrollTop', editor_scroll_handler);
        editor.session.setScrollTop((editor.session.getScreenLength() * \
            editor.renderer.lineHeight - $(editor.renderer.getContainerElement()).height()) * percentage)
        # re-attach other's scroll handler at the end, with some delay
        setTimeout (-> editor.session.on('changeScrollTop', editor_scroll_handler)), 20
    $html_div.scroll(html_scroll_handler)

