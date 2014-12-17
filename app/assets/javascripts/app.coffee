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
#    $("#md_editor_div").keydown ->
#        $("#md_html_div").html(marked(editor.getValue()))
    editor.on "change", ->
        $("#md_html_div").html(marked(editor.getValue()))
