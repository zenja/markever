"use strict"

markever = angular.module('markever', ['ngResource', 'ui.bootstrap', 'LocalStorageModule', 'angularUUID2'])

markever.controller 'EditorController',
['$scope', '$window', '$document', '$http', '$sce', '$interval',
 'localStorageService', 'enmlRenderer', 'scrollSyncor', 'apiClient', 'noteManager', 'imageManager', 'dbProvider',
 'notifier',
($scope, $window, $document, $http, $sce, $interval
 localStorageService, enmlRenderer, scrollSyncor, apiClient, noteManager, imageManager, dbProvider,
 notifier) ->
  vm = this

  # ------------------------------------------------------------------------------------------------------------------
  # Models
  # ------------------------------------------------------------------------------------------------------------------

  # ------------------------------------------------------------------------------------------------------------------
  # Debugging methods
  # ------------------------------------------------------------------------------------------------------------------
  vm._debug_show_current_note = () ->
    alert(JSON.stringify(vm.note))

  vm._debug_close_db = () ->
    dbProvider.close_db()
    alert('db closed!')

  vm._debug_show_current_note_in_db = () ->
    noteManager.find_note_by_guid(vm.get_guid()).then (note) =>
      alert('current note (' + vm.get_guid() + ') in db is: ' + JSON.stringify(note))

  # ------------------------------------------------------------------------------------------------------------------
  # App ready status
  # ------------------------------------------------------------------------------------------------------------------
  vm.all_ready = false

  # ------------------------------------------------------------------------------------------------------------------
  # Document ready
  # ------------------------------------------------------------------------------------------------------------------
  $document.ready ->
    # load ace editor
    $window.ace.config.set('basePath', '/javascripts/ace')
    vm.ace_editor = $window.ace.edit("md_editor_div")
    vm.ace_editor.renderer.setShowGutter(false)
    vm.ace_editor.setShowPrintMargin(false)
    vm.ace_editor.getSession().setMode("ace/mode/markdown")
    vm.ace_editor.getSession().setUseWrapMode(true)
    vm.ace_editor.setTheme('ace/theme/tomorrow_night_eighties')
    vm.ace_editor.on 'change', vm.editor_content_changed
    vm.ace_editor.focus()

    # sync scroll
    scrollSyncor.syncScroll(vm.ace_editor, $('#md_html_div'))

    noteManager.init_current_note()

    # get note list
    noteManager.fetch_note_list()

    # get notebook list
    noteManager.fetch_notebook_list()

    # take effect the settings
    vm.set_keyboard_handler(vm.current_keyboard_handler)
    vm.set_show_gutter(vm.current_show_gutter)
    vm.set_ace_theme(vm.current_ace_theme)

    # reset app status
    vm.reset_status()

    # all ready
    vm.all_ready = true

  # ------------------------------------------------------------------------------------------------------------------
  # ace editor event handlers
  # ------------------------------------------------------------------------------------------------------------------
  vm.editor_content_changed = (event) ->
    # render html, since noteManager will not notify back if use editor_content_changed(...)
    enmlRenderer.render_html($('#md_html_div'), vm.ace_editor.getValue())
    noteManager.editor_content_changed(vm.ace_editor.getValue())

  # ------------------------------------------------------------------------------------------------------------------
  # Operations for notes
  # ------------------------------------------------------------------------------------------------------------------
  vm.load_note = (guid) ->
    if guid != noteManager.get_current_note_guid()
      vm.open_loading_modal()
      noteManager.load_note(guid)

  vm.sync_up_all_notes = ->
    if vm.saving_note == false
      vm.saving_note = true
      p = noteManager.sync_up_all_notes($('#md_html_div_hidden')).then () =>
        notifier.success('sync_up_all_notes() succeeded for all notes!')
        vm.saving_note = false
      p.catch (error) =>
          notifier.error('vm.sync_up_all_notes() failed: ' + error)
          vm.saving_note = false

  # ------------------------------------------------------------------------------------------------------------------
  # TODO Note Manager Event Handlers
  # ------------------------------------------------------------------------------------------------------------------
  noteManager.on_current_note_md_modified (new_md) ->
    vm.ace_editor.setValue(new_md)
    enmlRenderer.render_html($('#md_html_div'), new_md).catch (error) =>
      notifier.error('render error: ' + error)
    console.log('on_current_note_md_modified()')

  noteManager.on_current_note_switched (new_note_guid) ->
    enmlRenderer.render_html($('#md_html_div'), noteManager.get_current_note_md())

  noteManager.on_note_load_finished (is_success, guid, error) ->
    vm.close_loading_modal()
    if is_success
      console.log('load note ' + guid + ' succeeded')
    else
      notifier.error('load note ' + guid + ' failed: ' + error)

  noteManager.on_note_synced (is_success, old_guid, new_guid, error) ->

  noteManager.on_note_list_changed (note_list) ->

  noteManager.on_notebook_list_changed (notebook_list) ->


  # ------------------------------------------------------------------------------------------------------------------
  # App Status
  # ------------------------------------------------------------------------------------------------------------------
  vm.saving_note = false
  # reset status
  vm.reset_status = ->
    # if the note is in process of saving (syncing) or not
    vm.saving_note = false

  # ------------------------------------------------------------------------------------------------------------------
  # Editor Settings
  # ------------------------------------------------------------------------------------------------------------------
  # settings name constants
  vm.SETTINGS_KEY =
    KEYBOARD_HANDLER: 'settings.keyboard_handler'
    SHOW_GUTTER: 'settings.show_gutter'
    ACE_THEME: 'settings.ace_theme'
    CURRENT_NOTE_GUID: 'settings.current_note.guid'

  # --------------------------------------------------------
  # Editor Keyboard Handler Settings
  # --------------------------------------------------------
  vm.keyboard_handlers = [
    {name: 'normal', id: ''}
    {name: 'vim', id: 'ace/keyboard/vim'}
  ]
  # load settings from local storage
  if localStorageService.get(vm.SETTINGS_KEY.KEYBOARD_HANDLER) != null
    # N.B. should be set to reference, not value!
    saved_handler = localStorageService.get(vm.SETTINGS_KEY.KEYBOARD_HANDLER)
    for handler in vm.keyboard_handlers
      if saved_handler.name == handler.name
        vm.current_keyboard_handler = handler
        break
  else
    vm.current_keyboard_handler = vm.keyboard_handlers[0]
  # "new" keyboard handler used in settings modal
  # N.B. must by reference, not value
  # refer: http://jsfiddle.net/qWzTb/
  # and: https://docs.angularjs.org/api/ng/directive/select
  vm.new_keyboard_handler = vm.current_keyboard_handler
  vm.set_keyboard_handler = (handler) ->
    vm.ace_editor.setKeyboardHandler(handler.id)
    vm.current_keyboard_handler = handler
    localStorageService.set(vm.SETTINGS_KEY.KEYBOARD_HANDLER, JSON.stringify(handler))

  # --------------------------------------------------------
  # Editor Gutter Settings
  # --------------------------------------------------------
  if localStorageService.get(vm.SETTINGS_KEY.KEYBOARD_HANDLER) != null
    vm.current_show_gutter = JSON.parse(localStorageService.get(vm.SETTINGS_KEY.SHOW_GUTTER))
  else
    vm.current_show_gutter = false
  vm.new_show_gutter = vm.show_gutter
  vm.set_show_gutter = (is_show) ->
    vm.ace_editor.renderer.setShowGutter(is_show)
    vm.current_show_gutter = is_show
    localStorageService.set(vm.SETTINGS_KEY.SHOW_GUTTER, JSON.stringify(is_show))

  # --------------------------------------------------------
  # Editor Theme Settings
  # --------------------------------------------------------
  vm.ace_themes = [
    {name: 'default', id: ''}
    {name: 'ambiance', id: 'ace/theme/ambiance'}
    {name: 'chaos', id: 'ace/theme/chaos'}
    {name: 'chrome', id: 'ace/theme/chrome'}
    {name: 'clouds', id: 'ace/theme/clouds'}
    {name: 'clouds_midnight', id: 'ace/theme/clouds_midnight'}
    {name: 'cobalt', id: 'ace/theme/cobalt'}
    {name: 'crimson_editor', id: 'ace/theme/crimson_editor'}
    {name: 'dawn', id: 'ace/theme/dawn'}
    {name: 'dreamweaver', id: 'ace/theme/dreamweaver'}
    {name: 'eclipse', id: 'ace/theme/eclipse'}
    {name: 'github', id: 'ace/theme/github'}
    {name: 'idle_fingers', id: 'ace/theme/idle_fingers'}
    {name: 'katzenmilch', id: 'ace/theme/katzenmilch'}
    {name: 'kr_theme', id: 'ace/theme/kr_theme'}
    {name: 'kuroir', id: 'ace/theme/kuroir'}
    {name: 'merbivore', id: 'ace/theme/merbivore'}
    {name: 'merbivore_soft', id: 'ace/theme/merbivore_soft'}
    {name: 'mono_industrial', id: 'ace/theme/mono_industrial'}
    {name: 'monokai', id: 'ace/theme/monokai'}
    {name: 'pastel_on_dark', id: 'ace/theme/pastel_on_dark'}
    {name: 'solarized_dark', id: 'ace/theme/solarized_dark'}
    {name: 'solarized_light', id: 'ace/theme/solarized_light'}
    {name: 'terminal', id: 'ace/theme/terminal'}
    {name: 'textmate', id: 'ace/theme/textmate'}
    {name: 'tomorrow', id: 'ace/theme/tomorrow'}
    {name: 'tomorrow_night', id: 'ace/theme/tomorrow_night'}
    {name: 'tomorrow_night_blue', id: 'ace/theme/tomorrow_night_blue'}
    {name: 'tomorrow_night_bright', id: 'ace/theme/tomorrow_night_bright'}
    {name: 'tomorrow_night_eighties', id: 'ace/theme/tomorrow_night_eighties'}
    {name: 'twilight', id: 'ace/theme/twilight'}
    {name: 'vibrant_ink', id: 'ace/theme/vibrant_ink'}
    {name: 'xcode', id: 'ace/theme/xcode'}
  ]
  if localStorageService.get(vm.SETTINGS_KEY.ACE_THEME) != null
    # N.B. should be set to reference, not value!
    saved_ace_theme = localStorageService.get(vm.SETTINGS_KEY.ACE_THEME)
    for theme in vm.ace_themes
      if saved_ace_theme.name == theme.name
        vm.current_ace_theme = theme
        break
  else
    vm.current_ace_theme = vm.ace_themes[0]
  # "new" ace theme used in settings modal
  # N.B. same, must by reference, not value
  vm.new_ace_theme = vm.current_ace_theme
  vm.set_ace_theme = (theme) ->
    vm.ace_editor.setTheme(theme.id)
    vm.current_ace_theme = theme
    localStorageService.set(vm.SETTINGS_KEY.ACE_THEME, JSON.stringify(theme))

  # ------------------------------------------------------------------------------------------------------------------
  # on paste
  # ------------------------------------------------------------------------------------------------------------------
  vm.handle_paste = (e) =>
    if not vm.ace_editor.isFocused
      return false
    items = (e.clipboardData || e.originalEvent.clipboardData).items
    console.log(JSON.stringify(items))
    if items[0].type.match(/image.*/)
      blob = items[0].getAsFile()
      image_uuid = imageManager.load_image_blob(blob)
      vm.ace_editor.insert('![Alt text](' + image_uuid + ')')

  # ------------------------------------------------------------------------------------------------------------------
  # settings modal
  # ------------------------------------------------------------------------------------------------------------------
  vm.open_settings_modal = ->
    # reset "new" settings to current settings
    vm.new_keyboard_handler = vm.current_keyboard_handler
    vm.new_ace_theme = vm.current_ace_theme
    vm.new_show_gutter = vm.current_show_gutter
    # show modal
    $('#settings-modal').modal({})
    # explicit return non-DOM result to avoid warning
    return true

  vm.save_settings = ->
    vm.set_ace_theme(vm.new_ace_theme)
    vm.set_keyboard_handler(vm.new_keyboard_handler)
    vm.set_show_gutter(vm.new_show_gutter)

  # ------------------------------------------------------------------------------------------------------------------
  # note list modal
  # ------------------------------------------------------------------------------------------------------------------
  vm.open_note_list_modal = ->
    # clear search keyword
    vm.search_note_keyword = ''

    note_list = noteManager.get_note_list()
    notebook_list = noteManager.get_notebook_list()
    notebook_name_map = {}
    notebook_collapse_map = {}
    for nb in notebook_list
      notebook_name_map[nb.guid] = nb.name
      notebook_collapse_map[nb.guid] = true
    # key: notebook guid; value: Map{notebook_name: String, note_list: Array}
    note_group_list = {}
    for n in note_list
      if not (n.notebook_guid of note_group_list)
        if n.notebook_guid.trim() == ""
          note_group_list[n.notebook_guid] =
            notebook_name: 'Unspecified Notebook'
            note_list: []
        else
          note_group_list[n.notebook_guid] =
            notebook_name: notebook_name_map[n.notebook_guid]
            note_list: []
      note_group_list[n.notebook_guid].note_list.push(n)
    if not vm.notebook_collapse_map?
      vm.notebook_collapse_map = notebook_collapse_map
    vm.note_group_list = note_group_list
    $('#note_list_div').modal({})
    # explicit return non-DOM result to avoid warning
    return true

  # ------------------------------------------------------------------------------------------------------------------
  # toolbar
  # ------------------------------------------------------------------------------------------------------------------

  # ------------------------------------------------------------------------------------------------------------------
  # loading modal
  # ------------------------------------------------------------------------------------------------------------------
  vm.open_loading_modal = ->
    $('#loading-modal').modal({
      backdrop: 'static'
      keyboard: false
    })

  vm.close_loading_modal = ->
    $('#loading-modal').modal('hide')

  # fixme for debug
  vm.note_manager = noteManager
]


# ----------------------------------------------------------------------------------------------------------------------
# Service: enmlRenderer
# ----------------------------------------------------------------------------------------------------------------------
markever.factory 'enmlRenderer', ['$window', 'imageManager', 'notifier', ($window, imageManager, notifier) ->
  render_html = (jq_html_div, md) ->
    processed_md = _md_pre_process(md)
    _html_dom = $('<div></div>')
    _html_dom.html($window.marked(processed_md, {sanitize: true}))
    return _html_post_process(_html_dom).then(
      () ->
        jq_html_div.empty()
        jq_html_div.append(_html_dom)
      (error) ->
        notifier.error('render_html() error: ' + error)
    )

  _md_pre_process = (md) ->
    # TODO more handling
    processed_md = md
    return processed_md

  # return promise
  _html_post_process = (jq_tmp_div) ->
    # code highlighting
    jq_tmp_div.find('pre code').each (i, block) ->
      hljs.highlightBlock(block)
    # render Latex
    $window.MathJax.Hub.Queue(['Typeset', $window.MathJax.Hub, jq_tmp_div.get(0)])
    # change img src to real data url
    must_finish_promise_list = []
    jq_tmp_div.find('img[src]').each (index) ->
      $img = $(this)
      uuid = $img.attr('src')
      p = imageManager.find_image_by_uuid(uuid).then(
        (image) =>
          if image?
            console.log('change img src from ' + uuid + ' to its base64 content')
            $img.attr('longdesc', uuid)
            $img.attr('src', image.content)
        (error) =>
          notifier.error('_html_post_process() failed due to failure in imageManager.find_image_by_uuid(' + uuid + '): ' + error)
      )
      must_finish_promise_list.push(p.catch (error) -> notifier.error('image replace failed: ' + error))
    return Promise.all(must_finish_promise_list).then () -> return jq_tmp_div


  get_enml_and_title_promise = (jq_html_div, markdown) ->
    return render_html(jq_html_div, markdown).then () =>
      # further post process
      # remove all script tags
      jq_html_div.find('script').remove()

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
          'size-matters' : ['SPAN'],
          'color-matters' : ['DIV', 'SPAN', 'PRE', 'CODE', 'BLOCKQUOTE', 'HR'],
          'position-matters' : ['DIV', 'PRE', 'BLOCKQUOTE', 'SPAN', 'HR', 'UL', 'OL', 'LI', 'P',
                      'H1', 'H2', 'H3', 'H4', 'H5', 'H6'],
          'border-matters' : ['HR', 'BLOCKQUOTE', 'SPAN', 'PRE', 'CODE'],
        }
      }
      jq_html_div.inlineStyler(inline_styler_option)

      # set href to start with 'http' is no protocol assigned
      jq_html_div.find('a').attr 'href', (i, href) ->
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
        allowedAttributes: [['href', ['a']], ['longdesc'], ['style']],
        removeAttrs: ['id', 'class', 'onclick', 'ondblclick', 'accesskey', 'data', 'dynsrc', 'tabindex',],
      }
      cleaned_html = $.htmlClean(jq_html_div.html(), html_clean_option);
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

      # make title
      title = 'New Note - Markever'
      if jq_html_div.find('h1').size() > 0
        text = jq_html_div.find('h1').text()
        title = text if text.trim().length > 0
      else if jq_html_div.find('h2').size() > 0
        text = jq_html_div.find('h2').text()
        title = text if text.trim().length > 0
      else if jq_html_div.find('h3').size() > 0
        text = jq_html_div.find('h3').text()
        title = text if text.trim().length > 0
      else if jq_html_div.find('p').size() > 0
        text = jq_html_div.find('p').text()
        title = text if text.trim().length > 0

      # the return value of result promise
      return {enml: final_note_xml, title: title}


  get_title_promise = (jq_html_div, markdown) ->
    return render_html(jq_html_div, markdown).then () =>
      title = 'New Note - Markever'
      if jq_html_div.find('h1').size() > 0
        text = jq_html_div.find('h1').text()
        title = text if text.trim().length > 0
      else if jq_html_div.find('h2').size() > 0
        text = jq_html_div.find('h2').text()
        title = text if text.trim().length > 0
      else if jq_html_div.find('h3').size() > 0
        text = jq_html_div.find('h3').text()
        title = text if text.trim().length > 0
      else if jq_html_div.find('p').size() > 0
        text = jq_html_div.find('p').text()
        title = text if text.trim().length > 0
      return title


  return {
    get_enml_and_title_promise : get_enml_and_title_promise
    get_title_promise: get_title_promise
    render_html: render_html
  }
]


# ----------------------------------------------------------------------------------------------------------------------
# Service: enmlRenderer
# ----------------------------------------------------------------------------------------------------------------------
markever.factory 'scrollSyncor', ->
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


# ----------------------------------------------------------------------------------------------------------------------
# Service: apiClient
# ----------------------------------------------------------------------------------------------------------------------
markever.factory 'apiClient', ['$resource', ($resource) -> new class APIClient
  note_resource: $resource('/api/v1/notes/:id', {id: '@id'}, {
    all: {method : 'GET', params : {id: ''}}
    note: {method : 'GET', params: {}}
    newest: {method : 'GET', params : {id: 'newest'}}
    save: {method : 'POST', params: {id: ''}}
  })

  notebook_resource: $resource('/api/v1/notebooks/:id', {id: '@id'}, {
    all: {method: 'GET', params: {id: ''}}
  })

  # return promise with all notes
  get_all_notes: () =>
    return @note_resource.all().$promise.then (data) =>
      return data['notes']

  # return promise with the note
  get_note: (guid) =>
    return @note_resource.note({id: guid}).$promise.then (data) =>
      return data.note

  # return promise with saved note that is returned from remote
  save_note: (guid, notebook_guid, title, enml) =>
    _post_data = {
      guid: guid
      notebookGuid: notebook_guid
      title: title
      enml: enml
    }
    return @note_resource.save(_post_data).$promise.then (data) =>
      return data.note

  get_all_notebooks: () =>
    return @notebook_resource.all().$promise.then (data) =>
      return data['notebooks']
]

# ----------------------------------------------------------------------------------------------------------------------
# Service: notifier
# ----------------------------------------------------------------------------------------------------------------------
markever.factory 'notifier', -> new class Notifier
  success: (msg) ->
    $.bootstrapGrowl(msg, {type: 'success'})

  error: (msg) ->
    $.bootstrapGrowl(msg, {type: 'danger'})

# ----------------------------------------------------------------------------------------------------------------------
# Service: dbProvider
# ----------------------------------------------------------------------------------------------------------------------
markever.factory 'dbProvider', -> new class DBProvider
  constructor: ->
    @db_server_promise = @init_db()

  init_db: () =>
    db_open_option = {
      server: 'markever'
      version: 1
      schema: {
        notes: {
          key: {keyPath: 'id', autoIncrement: true},
          indexes: {
            guid: {}
            title: {}
            notebook_guid: {}
            status: {}
            # no need to index md
            # md: {}
          }
        }
        images: {
          key: {keyPath: 'id', autoIncrement: true},
          indexes: {
            uuid: {}
            # no need to index content
            # content: {}
          }
        }
      }
    }
    # db.js promise is not real promise
    _false_db_p = db.open(db_open_option)
    return new Promise (resolve, reject) =>
      resolve(_false_db_p)

  get_db_server_promise: () =>
    console.log('return real promise @db_server_promise')
    if @db_server_promise?
      return @db_server_promise
    else
      return @init_db()

  close_db: () =>
    @db_server_promise.then (server) =>
      server.close()
      console.log('db closed')

# ----------------------------------------------------------------------------------------------------------------------
# Service: imageManager
# ----------------------------------------------------------------------------------------------------------------------
markever.factory 'imageManager', ['uuid2', 'dbProvider', (uuid2, dbProvider) -> new class ImageManager
  constructor: ->
    dbProvider.get_db_server_promise().then (server) =>
      @db_server = server
      console.log('DB initialized from ImageManager')

  # ------------------------------------------------------------
  # Return a copy of a image in db with a given uuid
  #
  # return: promise containing the image's info:
  #         uuid, content
  #         or null if image does not exist
  # ------------------------------------------------------------
  find_image_by_uuid: (uuid) =>
    p = new Promise (resolve, reject) =>
      resolve(@db_server.images.query().filter('uuid', uuid).execute())
    return p.then (images) =>
      if images.length == 0
        console.log('find_image_by_uuid(' + uuid + ') returned null')
        return null
      else
        console.log('find_image_by_uuid(' + uuid + ') hit')
        return images[0]

  # ------------------------------------------------------------
  # Add a image to db
  #
  # return: promise
  # ------------------------------------------------------------
  add_image: (uuid, content) =>
    console.log('Adding image to db - uuid: ' + uuid)
    return new Promise (resolve, reject) =>
      resolve(
        @db_server.images.add({
          uuid: uuid
          content: content
        })
      )

  # return: the uuid of the image (NOT promise)
  load_image_blob: (blob, extra_handler) =>
    uuid = uuid2.newuuid()
    reader = new FileReader()
    reader.onload = (event) =>
      console.log("image result: " + event.target.result)
      @add_image(uuid, event.target.result)
      # optional extra_handler
      if extra_handler
        extra_handler(event)
    # start reading blob data, and get result in base64 data URL
    reader.readAsDataURL(blob)
    return uuid
]

# ----------------------------------------------------------------------------------------------------------------------
# Service: noteManager
# ----------------------------------------------------------------------------------------------------------------------
markever.factory 'noteManager',
['$interval', 'uuid2', 'localStorageService', 'dbProvider', 'apiClient', 'imageManager', 'enmlRenderer', 'notifier',
($interval, uuid2, localStorageService, dbProvider, apiClient, imageManager, enmlRenderer, notifier) -> new class NoteManager

  #---------------------------------------------------------------------------------------------------------------------
  # Status of a note:
  # 1. new: note with a generated guid, not attached to remote
  # 2. synced_meta: note with metadata fetched to remote. not editable
  # 3. synced_all: note with all data synced with remote. editable
  # 4. modified: note attached to remote, but has un-synced modification
  #
  # Status transition:
  #
  #    sync        modify
  # new ------> synced_all ---------> modified
  #                  ^     <---------
  #                  |        sync
  #                  |
  #                  | load note data from remote
  #                  |
  # synced_meta ------
  #---------------------------------------------------------------------------------------------------------------------

  constructor: ->
    $interval(@save_current_note_to_db, 1000)

  NOTE_STATUS:
    NEW: 0
    SYNCED_META: 1
    SYNCED_ALL: 2
    MODIFIED: 3

  SETTINGS_KEY:
    CURRENT_NOTE_GUID: 'note_manager.settings.current_note.guid'


  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~| Current Note >

  current_note:
    guid: ''
    title: ''
    status: null
    md: ''
    notebook_guid: ''
    _is_dirty: false

  # ------------------------------------------------------------
  # Public accessor for current_note
  # ------------------------------------------------------------

  get_current_note_guid: =>
    return @current_note.guid

  get_current_note_title: =>
    return @current_note.title

  get_current_note_status: =>
    return @current_note.status

  get_current_note_md: =>
    return @current_note.md

  get_current_note_notebook_guid: =>
    return @current_note.notebook_guid

  # ------------------------------------------------------------
  # Private accessor for current_note
  # ------------------------------------------------------------

  _is_current_note_dirty: () =>
    return @current_note._is_dirty

  _set_current_note_dirty: (is_dirty) =>
    @current_note._is_dirty = is_dirty

  _switch_current_note: (guid, notebook_guid, title, md, status) =>
    console.log('_switch_current_note(...) invoked')
    @_set_current_note_guid(guid)
    if notebook_guid?
      @_set_current_note_notebook_guid(notebook_guid)
    if title?
      @_set_current_note_title(title)
    if md?
      if @get_current_note_md() != md
        @_set_current_note_md(md)
    if status?
      @_set_current_note_status(status)
    # notify event after current note changed
    @current_note_switched(guid)

  _set_current_note_guid: (guid) =>
    @current_note.guid = guid

  _set_current_note_title: (title) =>
    @current_note.title = title

  _set_current_note_md: (md, notify=true) =>
    if @get_current_note_md() != md
      @current_note.md = md
      if notify
        @current_note_md_modified(md)

    # change note status to MODIFIED if original status is SYNCED_ALL
    if @get_current_note_status() == @NOTE_STATUS.SYNCED_ALL
      @_set_current_note_status(@NOTE_STATUS.MODIFIED)

  _set_current_note_status: (status) =>
    @current_note.status = status
    @reload_local_note_list()

  _set_current_note_notebook_guid: (notebook_guid) =>
    @current_note.notebook_guid = notebook_guid
    @reload_local_note_list()

  # ------------------------------------------------------------
  # Other Operations for Current Note
  # ------------------------------------------------------------

  editor_content_changed: (md) =>
    if @get_current_note_md() != md
      # update md w/o notifying, otherwise will make loop
      @_set_current_note_md(md, false)
      @_set_current_note_dirty(true)

  save_current_note_to_db: () =>
    if @_is_current_note_dirty()
      console.log('current note is dirty, saving to db...')
      # FIXME remove jq element
      enmlRenderer.get_title_promise($('#md_html_div_hidden'), @get_current_note_md()).then (title) =>
        note_info =
          guid: @get_current_note_guid()
          notebook_guid: @get_current_note_notebook_guid()
          title: title
          md: @get_current_note_md()
          status: @get_current_note_status()
        @update_note(note_info).then(
          (note) =>
            console.log('dirty note successfully saved to db: ' + JSON.stringify(note) + ', set it to not dirty.')
            # because title may change, we need to reload note list
            @reload_local_note_list()
            @_set_current_note_dirty(false)
          (error) =>
            notifier.error('update note failed in save_current_note_to_db(): ' + JSON.stringify(error))
        ).catch (error) => notifier.error('failed to save current note to db: ' + error)

  # ------------------------------------------------------------
  # load previous note if exists, otherwise make a new note and set it current note
  # ------------------------------------------------------------
  init_current_note: () =>
    previous_note_guid = localStorageService.get(@SETTINGS_KEY.CURRENT_NOTE_GUID)
    if previous_note_guid? == false
      previous_note_guid = "INVALID_GUID"
    p = @find_note_by_guid(previous_note_guid).then (note) =>
      if note?
        console.log('got valid previous current note ' + previous_note_guid + '. load...')
        @load_note(note.guid)
      else
        console.log('no valid previous current note found. create new note')
        @make_new_note().then(
          (note) =>
            @_switch_current_note(note.guid, note.notebook_guid, note.title, note.md, @NOTE_STATUS.NEW)
            console.log('New note made: ' + JSON.stringify(note))
          (error) =>
            notifier.error('make_new_note() failed: ' + error)
        ).catch (error) =>
          trace = printStackTrace({e: error})
          notifier.error('Error, make new note failed!\n' + 'Message: ' + error.message + '\nStack trace:\n' + trace.join('\n'))
    p.catch (error) => notifier.error('load previous current note failed: ' + error)

  # ------------------------------------------------------------
  # Load a note by guid as current note
  #
  # If note is SYNCED_ALL in local, just load it from local
  # otherwise fetch the note content from remote
  #
  # Return:
  # ------------------------------------------------------------
  load_note: (guid) =>
    # check if the note to be loaded is already current note
    if guid != @get_current_note_guid()
      p = @find_note_by_guid(guid).then (note) =>
        if note? and
          (note.status == @NOTE_STATUS.NEW or
          note.status == @NOTE_STATUS.SYNCED_ALL or
          note.status == @NOTE_STATUS.MODIFIED)
            # note in db -> current note
            console.log('loading note ' + note.guid + ' with status ' + note.status + ' from local DB')
            @_switch_current_note(note.guid, note.notebook_guid, note.title, note.md, note.status)
            @note_load_finished(true, note.guid, null)
            console.log('loading note ' + note.guid + ' finished')
        if (note? == false) or (note.status == @NOTE_STATUS.SYNCED_META)
          # remote note -> current note
          @fetch_remote_note(guid).then(
            (note) =>
              console.log('loading note ' + note.guid + ' with status ' + note.status + ' from remote')
              @_switch_current_note(note.guid, note.notebook_guid, note.title, note.md, note.status)
              @note_load_finished(true, note.guid, null)
              console.log('loading note ' + note.guid + ' finished')
              # updating note list
              @get_all_notes().then(
                (notes) =>
                  console.log('updating note lists')
                  @_set_note_list(notes)
                (error) =>
                  notifier.error('get_all_notes() failed in load_note(): ' + error)
              )
            (error) =>
              notifier.error('load note ' + guid + ' failed: ' + JSON.stringify(error))
              @note_load_finished(false, guid, new Error('load note ' + guid + ' failed: ' + JSON.stringify(error)))
          )
      p.catch (error) =>
        notifier.error('find_note_by_guid() itself or then() failed in load_note(): ' + JSON.stringify(error))

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~| Note List >

  note_list: []

  get_note_list: =>
    return @note_list

  _set_note_list: (note_list) =>
    @note_list = note_list
    @note_list_changed(note_list)

  # FIXME: delete previous comment when refactor is done
  fetch_note_list: =>
    @load_remote_notes().then(
      (notes) =>
        console.log('fetch_note_list() result: ' + JSON.stringify(notes))
        @_set_note_list(notes)
      (error) =>
        notifier.error('fetch_note_list() failed: ' + JSON.stringify(error))
    )

  reload_local_note_list: () =>
    p = @get_all_notes().then (notes) =>
      @_set_note_list(notes)
    p.catch (error) => notifier.error('reload_local_note_list() failed:' + error)

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~| Notebook List >

  notebook_list: []

  get_notebook_list: =>
    return @notebook_list

  _set_notebook_list: (notebook_list) =>
    @notebook_list = notebook_list
    @notebook_list_changed(notebook_list)

  fetch_notebook_list: =>
    @load_remote_notebooks().then(
      (notebooks) =>
        console.log('fetch_notebook_list() result: ' + JSON.stringify(notebooks))
        @_set_notebook_list(notebooks)
      (error) =>
        notifier.error('fetch_notebook_list() failed: ' + JSON.stringify(error))
    )

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~| Event System >

  # ------------------------------------------------------------
  # Event: current note markdown changed
  # ------------------------------------------------------------
  current_note_md_modified_listeners: []
  on_current_note_md_modified: (listener) =>
    @current_note_md_modified_listeners.push(listener)
  current_note_md_modified: (new_md) =>
    for l in @current_note_md_modified_listeners
      l(new_md)

  # ------------------------------------------------------------
  # Event: current note switched to another note
  # ------------------------------------------------------------
  current_note_switched_listeners: []
  on_current_note_switched: (listener) =>
    @current_note_switched_listeners.push(listener)
  current_note_switched: (new_note_guid) =>
    localStorageService.set(@SETTINGS_KEY.CURRENT_NOTE_GUID, new_note_guid)

    for l in @current_note_switched_listeners
      l(new_note_guid)

  # ------------------------------------------------------------
  # Event: current note's guid changed (the note is still the "same" note)
  # ------------------------------------------------------------
  current_note_guid_modified_listeners: []
  on_current_note_guid_modified: (listener) =>
    @current_note_guid_modified_listeners.push(listener)
  current_note_guid_modified: (old_guid, new_guid) =>
    localStorageService.set(@SETTINGS_KEY.CURRENT_NOTE_GUID, new_guid)

    for l in @current_note_guid_modified_listeners
      l(old_guid, new_guid)

  # ------------------------------------------------------------
  # Event: a note finished synced up
  # ------------------------------------------------------------
  note_synced_listeners: []
  on_note_synced: (listener) =>
    @note_synced_listeners.push(listener)
  note_synced: (is_success, old_guid, new_guid, error) =>
    @reload_local_note_list()

    for l in @note_synced_listeners
      l(is_success, old_guid, new_guid, error)

  # ------------------------------------------------------------
  # Event: note list changed
  # ------------------------------------------------------------
  note_list_changed_listeners: []
  on_note_list_changed: (listener) =>
    @note_list_changed_listeners.push(listener)
  note_list_changed: (note_list) =>
    for l in @note_list_changed_listeners
      l(note_list)

  # ------------------------------------------------------------
  # Event: a note finished loading (either success or fail)
  # ------------------------------------------------------------
  note_load_finished_listeners: []
  on_note_load_finished: (listener) =>
    @note_load_finished_listeners.push(listener)
  note_load_finished: (is_success, guid, error) =>
    for l in @note_load_finished_listeners
      l(is_success, guid, error)

  # ------------------------------------------------------------
  # Event: a note finished loading (either success or fail)
  # ------------------------------------------------------------
  notebook_list_changed_listeners: []
  on_notebook_list_changed: (listener) =>
    @notebook_list_changed_listeners.push(listener)
  notebook_list_changed: (notebook_list) =>
    for l in @notebook_list_changed_listeners
      l(notebook_list)

  # ------------------------------------------------------------
  # Event: a note finished loading (either success or fail)
  # ------------------------------------------------------------
  new_note_made_listeners: []
  on_new_note_made: (listener) =>
    @new_note_made_listeners.push(listener)
  new_note_made: () =>
    console.log('refresh local note list due to new note made')
    @reload_local_note_list()

    for l in @new_note_made_listeners
      l()

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~| Remote Operations >

  # ------------------------------------------------------------
  # Fetch a remote note's all info by guid and update db
  #
  # check if note is in local and is SYNCED_ALL first
  # return: promise containing note's info
  # ------------------------------------------------------------
  fetch_remote_note: (guid) =>
    console.log('fetch_remote_note(' + guid + ') begins to invoke')
    return @find_note_by_guid(guid).then (note) =>
      console.log('fetch_remote_note(' + guid + ') local note: ' + JSON.stringify(note))
      if note != null && note.status == @NOTE_STATUS.SYNCED_ALL
        console.log('Local note fetch hit: ' + JSON.stringify(note))
        return note
      else
        console.log('Local note fetch missed, fetch from remote: ' + guid)
        return apiClient.get_note(guid).then (note) =>
          _note =
            guid: guid
            notebook_guid: note.notebook_guid
            title: note.title
            md: note.md
            status: @NOTE_STATUS.SYNCED_ALL
            resources: note.resources
          return @update_note(_note)

  # ------------------------------------------------------------
  # Load remote note list (only metadata) to update local notes info
  # return: promise
  # ------------------------------------------------------------
  load_remote_notes: =>
    # TODO handle failure
    return apiClient.get_all_notes().then (notes) =>
      @_merge_remote_notes(notes).then(
        () =>
          console.log('finish merging remote notes')
          return @get_all_notes()
        (error) =>
          # TODO pass error on
          notifier.error('_merge_remote_notes() failed!')
      )

  # ------------------------------------------------------------
  # Load remote notebook list (only name and guid) to update local notebooks info
  # return: promise
  # ------------------------------------------------------------
  load_remote_notebooks: =>
    # TODO handle failure
    return apiClient.get_all_notebooks().then (notebooks) =>
      return notebooks

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~| Merge/Sync Operations >

  # ------------------------------------------------------------
  # merge remote note list into local note list db
  # Possible situations: TODO
  # ------------------------------------------------------------
  _merge_remote_notes: (notes) =>
    guid_list = (note['guid'] for note in notes)
    console.log('start merging remote notes: ' + JSON.stringify(guid_list))

    must_finish_promise_list = []
    remote_note_guid_list = []

    # Phase one: patch remote notes to local
    for note_meta in notes
      remote_note_guid_list.push(note_meta['guid'])
      do (note_meta) =>
        guid = note_meta['guid']
        title = note_meta['title']
        notebook_guid = note_meta['notebook_guid']
        console.log('Merging note [' + guid + ']')

        find_p = @find_note_by_guid(guid).then (note) =>
          _find_p_must_finish_promise_list = []
          if note == null
            console.log('About to add note ' + guid)
            p = @add_note_meta({
              guid: guid
              title: title
              notebook_guid: notebook_guid
            }).then () => console.log('note ' + guid + ' metadata added!')
            _find_p_must_finish_promise_list.push(p)
            console.log('pushed to _find_p_must_finish_promise_list. TAG: A')

          else
            console.log('local note ' + guid + ' exists, updating from remote.')
            switch note.status
              when @NOTE_STATUS.NEW
                console.log('[IMPOSSIBLE] remote note\'s local cache is in status NEW')

              when @NOTE_STATUS.SYNCED_META
                # update note title
                p = @update_note({
                  guid: guid
                  title: title
                  notebook_guid: notebook_guid
                })
                _find_p_must_finish_promise_list.push(p)
                console.log('pushed to _find_p_must_finish_promise_list. TAG: B')

              when @NOTE_STATUS.SYNCED_ALL
                # fetch the whole note from server and update local
                console.log('local note ' + guid + ' is SYNCED_ALL, about to fetch from remote for updating')
                @fetch_remote_note(guid).then(
                  (note) =>
                    console.log('note ' + guid + ' (SYNCED_ALL) updated from remote')
                    # maybe FIXME did not add to promise waiting list
                    #_find_p_must_finish_promise_list.push(p)
                    #console.log('pushed to _find_p_must_finish_promise_list. TAG: C')
                  (error) =>
                    notifier.error('fetch note ' + guid + ' failed during _merge_remote_notes():' + JSON.stringify(error))
                )

              when @NOTE_STATUS.MODIFIED
                # do nothing
                console.log('do nothing')

              else
                notifier.error('IMPOSSIBLE: no correct note status')
          return Promise.all(_find_p_must_finish_promise_list)
        must_finish_promise_list.push(find_p)
        console.log('pushed to must_finish_promise_list. TAG: D')

    # Phase two: deleted local notes not needed
    # Notes that should be deleted:
    # not in remote and status is not new/modified
    p = @get_all_notes().then (notes) =>
      for n in notes
        if (n.guid not in remote_note_guid_list) && n.status != @NOTE_STATUS.NEW && n.status != @NOTE_STATUS.MODIFIED
          _p = @delete_note(n.guid)
          must_finish_promise_list.push(_p)
          console.log('pushed to must_finish_promise_list. TAG: E')
    must_finish_promise_list.push(p)
    console.log('pushed to must_finish_promise_list. TAG: F')

    console.log('about to return from _merge_remote_notes(). promise list: ' + JSON.stringify(must_finish_promise_list))
    console.log('check if promises in promise list is actually Promises:')
    for p in must_finish_promise_list
      if p instanceof Promise
        console.log('is Promise!')
      else
        console.log('is NOT Promise!!')
    return Promise.all(must_finish_promise_list)

  # ------------------------------------------------------------
  # Params:
  #   jq_div: jQuery div element for rendering
  #   one_note_synced_func: function called whenever a note is successfully synced up
  # ------------------------------------------------------------
  sync_up_all_notes: (jq_div) =>
    p = @get_all_notes().then (notes) =>
      _must_finish_promise_list = []
      for note in notes
        guid = note.guid
        notebook_guid = note.notebook_guid
        md = note.md

        if note.status == @NOTE_STATUS.NEW || note.status == @NOTE_STATUS.MODIFIED
          is_new_note = (note.status == @NOTE_STATUS.NEW)
          console.log('note ' + guid + ' sent for sync up')
          _p = @sync_up_note(is_new_note, guid, notebook_guid, jq_div, md).then(
            (synced_note) =>
              console.log('sync up note ' + guid + ' succeeded')
              @note_synced(true, guid, synced_note.guid, null)
            (error) =>
              notifier.error('sync up note ' + guid + ' failed: ' + JSON.stringify(error))
              @note_synced(false, null, null, error)
          )
          _must_finish_promise_list.push(_p)
      return Promise.all(_must_finish_promise_list)

    return p.catch (error) =>
      trace = printStackTrace({e: error})
      notifier.error('sync_up_all_notes() failed\n' + 'Message: ' + error.message + '\nStack trace:\n' + trace.join('\n'))

  # ------------------------------------------------------------
  # return Promise containing the synced note
  # ------------------------------------------------------------
  sync_up_note: (is_new_note, guid, notebook_guid, jq_div, md) =>
    console.log('enter sync_up_note() for note ' + guid)
    return enmlRenderer.get_enml_and_title_promise(jq_div, md).then (enml_and_title) =>
      title = enml_and_title.title
      enml = enml_and_title.enml
      request_guid = guid
      if is_new_note
        request_guid = ''
      return apiClient.save_note(request_guid, notebook_guid, title, enml).then(
        (note) =>
          # 1. change note status to SYNCED_ALL, using old guid
          _modify =
            guid: guid
            status: @NOTE_STATUS.SYNCED_ALL
          # 2. update notebook_guid if it is set a new one from remote
          if notebook_guid != note.notebook_guid
            _modify['notebook_guid'] = note.notebook_guid
          p = @update_note(_modify).then () =>
            # 3. update guid if is new note (when saving new note, tmp guid will be updated to real one)
            if is_new_note
              new_guid = note.guid
              # @update_note_guid will return Promise containing the updated note
              return @update_note_guid(guid, new_guid)
            else
              return @find_note_by_guid(guid)
          return p
          console.log('sync_up_note(' + guid + ') succeed')
        (error) =>
          # set status back
          notifier.error('sync_up_note() failed: \n' + JSON.stringify(error))
          throw error
      )

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~| DB Operations >

  # db server safe. will get db server itself
  get_all_notes: () =>
    console.log('get_all_notes() invoked')
    return dbProvider.get_db_server_promise().then (server) =>
      return server.notes.query().all().execute()

  # ------------------------------------------------------------
  # make a new note to db
  #
  # db server safe. will get db server itself
  # return promise
  # ------------------------------------------------------------
  make_new_note: () =>
    console.log('make_new_note() invoking')
    return new Promise (resolve, reject) =>
      guid = uuid2.newguid() + '-new'
      db_server_p = new Promise (resolve, reject) =>
        # db.js does not return real Promise...
        _false_p = dbProvider.get_db_server_promise().then (server) =>
            server.notes.add({
              guid: guid
              title: 'New Note'
              md: 'New Note\n==\n'
              notebook_guid: ''
              status: @NOTE_STATUS.NEW
            })
        resolve(_false_p)
      p = db_server_p.then(
        () =>
          return @find_note_by_guid(guid)
        (error) =>
          notifier.error('make_new_note() error!')
      )
      resolve(p)

  # db server safe. will get db server itself
  delete_note: (guid) =>
    console.log('delete_note(' + guid + ') invoked')
    return @find_note_by_guid(guid).then(
      (note) =>
        if note is null
          console.log('cannot delete note null, aborted')
        else
          console.log('about to remove note id ' + note.id)
          p = dbProvider.get_db_server_promise().then (server) =>
            server.notes.remove(note.id)
            console.log('local note ' + note.guid + ' deleted. id: ' + note.id)
          p.catch (error) =>
            notifier.error('delete_note(' + guid + ') failed')
      (error) =>
        notifier.error('error!')
    )

  # ------------------------------------------------------------
  # Return a copy of a note in db with a given guid
  #
  # db server safe. will get db server itself
  # return: promise containing the note's info,
  #         or null if note does not exist
  # ------------------------------------------------------------
  find_note_by_guid: (guid) =>
    # db.js then() does not return a Promise,
    # need to be wrapper in a real Promise
    p = dbProvider.get_db_server_promise().then (server) =>
      return new Promise (resolve, reject) =>
        resolve(server.notes.query().filter('guid', guid).execute())
    return p.then (notes) =>
      if notes.length == 0
        console.log('find_note_by_guid(' + guid + ') returned null')
        return null
      else
        console.log('find_note_by_guid(' + guid + ') hit')
        return notes[0]

  # ------------------------------------------------------------
  # Add a note's metadata which to db
  #
  # db server safe. will get db server itself
  # return: promise
  # ------------------------------------------------------------
  add_note_meta: (note) ->
    console.log('Adding note to db - guid: ' + note.guid +
      ' title: ' + note.title +
      ' notebook_guid: ' + note.notebook_guid)
    return dbProvider.get_db_server_promise().then (server) =>
      return new Promise (resolve, reject) =>
        resolve(
          server.notes.add({
            guid: note.guid
            title: note.title
            notebook_guid: note.notebook_guid
            status: @NOTE_STATUS.SYNCED_META
          })
        )

  # ------------------------------------------------------------
  # Update a note, except for its guid
  #
  # db server safe. will get db server itself
  # If need to update note's guid, please use update_note_guid()
  #
  # return: promise
  # ------------------------------------------------------------
  update_note: (note) =>
    console.log('update_note(' + note.guid + ') invoking')
    if note.guid? == false
      notifier.error('update_note(): note to be updated must have a guid!')
      return new Promise (resolve, reject) =>
        reject(new Error('update_note(): note to be updated must have a guid!'))

    # register resource data into ImageManager
    if note.resources?
      for r in note.resources
        imageManager.add_image(r.uuid, r.data_url).catch (error) =>
          notifier.error('add image failed! uuid: ' + r.uuid)
        console.log("register uuid: " + r.uuid + " data len: " + r.data_url.length)
    # update notes db
    p = new Promise (resolve, reject) =>
      _note_modify = {}
      if note.title?
        _note_modify.title = note.title
      if note.md?
        _note_modify.md = note.md
      if note.notebook_guid?
        _note_modify.notebook_guid = note.notebook_guid
      if note.status?
        _note_modify.status = note.status
      _modify_p = dbProvider.get_db_server_promise().then (server) =>
          return server.notes.query().filter('guid', note.guid).modify(_note_modify).execute()
      resolve(_modify_p)
    return p.then(
      () =>
        console.log('update note ' + note.guid + ' successfully')
        return @find_note_by_guid(note.guid)
      (error) =>
        notifier.error('update note ' + note.guid + ' failed!')
    )

  # return promise containing the updated note
  update_note_guid: (old_guid, new_guid) =>
    p = @find_note_by_guid(old_guid).then (note) =>
      if note?
        _modify_p = dbProvider.get_db_server_promise().then (server) =>
          _note_modify = {guid: new_guid}
          return server.notes.query().filter('guid', old_guid).modify(_note_modify).execute()
        return _modify_p
      else
        console.log('update note guid ' + old_guid + ' to new guid ' + new_guid + ' missed!')
    return p.then(
      () =>
        console.log('update note guid ' + old_guid + ' to new guid ' + new_guid + ' succeed')
        # notify current note guid changed
        if old_guid == @current_note.guid
          @current_note_guid_modified(old_guid, new_guid)
        return @find_note_by_guid(new_guid)
      (error) =>
        notifier.error('update note guid ' + old_guid + ' to new guid ' + new_guid + ' failed: ' + error)
    )

  # ------------------------------------------------------------
  # Clear db
  #
  # db server safe. will get db server itself
  # return: promise
  # ------------------------------------------------------------
  clear_all_notes: () ->
    return dbProvider.get_db_server_promise().then (server) =>
      server.notes.clear()

  # --------------------------------- tmp operations --------------------------------
]

