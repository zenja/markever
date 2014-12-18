$ ->
    # ace editor creation and conf
    editor = ace.edit("md_editor_div");
    editor.setShowPrintMargin(false);
    editor.getSession().setMode("ace/mode/markdown");
    editor.getSession().setUseWrapMode(true);

    # "show html" link for debugging
    $("a#show_html").click ->
        alert(marked(editor.getValue()))

    # auto-generate html when editing markdown
    editor.on "change", ->
        $("#md_html_div").html(marked(editor.getValue()))
        $('pre code').each (i, block) ->
            hljs.highlightBlock(block)
        # render Latax
        MathJax.Hub.Queue(["Typeset", MathJax.Hub, $("#md_html_div").get(0)])

    # sync scroll between two columns
    # check: http://stackoverflow.com/questions/18952623/synchronized-scrolling-using-jquery
    # sync scroll: md -> html
    editor_scroll_handler = (scroll) =>
        percentage = scroll / (editor.session.getScreenLength() * \
            editor.renderer.lineHeight - ($(editor.renderer.getContainerElement()).height()))
        if percentage > 1 or percentage < 0 then return
        percentage = Math.floor(percentage * 1000) / 1000;
        # detach other's scroll handler first
        $("#md_html_div").off('scroll', html_scroll_handler)
        md_html_div = $("#md_html_div").get(0)
        md_html_div.scrollTop = percentage * (md_html_div.scrollHeight - md_html_div.offsetHeight)
        # re-attach other's scroll handler at the end, with some delay
        setTimeout (-> $("#md_html_div").scroll(html_scroll_handler)), 10
    editor.session.on('changeScrollTop', editor_scroll_handler)

    # sync scroll: html -> md
    html_scroll_handler = (e) =>
        md_html_div = $("#md_html_div").get(0)
        percentage = md_html_div.scrollTop / (md_html_div.scrollHeight - md_html_div.offsetHeight)
        if percentage > 1 or percentage < 0 then return
        percentage = Math.floor(percentage * 1000) / 1000;
        # detach other's scroll handler first
        editor.getSession().removeListener('changeScrollTop', editor_scroll_handler);
        editor.session.setScrollTop((editor.session.getScreenLength() * \
            editor.renderer.lineHeight - $(editor.renderer.getContainerElement()).height()) * percentage)
        # re-attach other's scroll handler at the end, with some delay
        setTimeout (-> editor.session.on('changeScrollTop', editor_scroll_handler)), 20
    $("#md_html_div").scroll(html_scroll_handler)
