$ ->
    $("a#show_html").click ->
        alert(marked($("#md_editor_textarea").val()))
    $("#md_editor_textarea").keydown ->
        $("#md_html_div").html(marked($("#md_editor_textarea").val()))