$(document).ready(function() {
    var opts = {
      container: 'epiceditor',
      textarea: null,
      basePath: 'epiceditor',
      clientSideStorage: true,
      localStorageName: 'epiceditor',
      useNativeFullscreen: false,
      parser: marked,
      file: {
        name: 'epiceditor',
        defaultContent: '',
        autoSave: 100
      },
      theme: {
        base: '/themes/base/epiceditor.css',
        preview: '/themes/preview/preview-dark.css',
        editor: '/themes/editor/epic-dark.css'
      },
      button: {
        preview: true,
        fullscreen: true,
        bar: "auto"
      },
      focusOnLoad: false,
      shortcut: {
        modifier: 18,
        fullscreen: 70,
        preview: 80
      },
      string: {
        togglePreview: 'Toggle Preview Mode',
        toggleEdit: 'Toggle Edit Mode',
        toggleFullscreen: 'Enter Fullscreen'
      },
      autogrow: false
    }
    var editor = new EpicEditor().load();

    $("a#show_html").click(function() {
        alert(editor.getElement('editor').body.innerHTML);
    });

    $("a#preview").click(function() {
        editor.preview();
    });
});