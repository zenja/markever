"use strict"

markever = angular.module('markever', ['ngResource', 'ui.bootstrap', 'LocalStorageModule', 'angularUUID2'])

markever.controller 'EditorController',
['$scope', '$window', '$document', '$http', '$sce', '$interval'
 'localStorageService', 'enmlRenderer', 'scrollSyncor', 'apiClient', 'noteManager', 'imageManager', 'dbProvider'
($scope, $window, $document, $http, $sce, $interval
 localStorageService, enmlRenderer, scrollSyncor, apiClient, noteManager, imageManager, dbProvider) ->
  vm = this

  # ------------------------------------------------------------------------------------------------------------------
  # Models for notes
  # ------------------------------------------------------------------------------------------------------------------
  # current note
  vm.note =
    guid: ""
    title: ""
    _markdown: ""
    _is_dirty: false

  vm.get_guid = ->
    return vm.note.guid

  vm.set_guid = (guid) ->
    vm.note.guid = guid

  vm.get_title = ->
    return vm.note.title

  vm.set_title = (title) ->
    vm.note.title = title

  # markdown should only be get from this getter
  vm.get_md = ->
    return vm.note._markdown

  vm.set_md = (md) ->
    vm.note._markdown = md
    vm.set_note_dirty(true)

  vm.set_md_and_update_editor = (md) ->
    vm.set_md(md)
    vm.ace_editor.setValue(md)

  vm.is_note_dirty = () ->
    return vm.note._is_dirty

  vm.set_note_dirty = (is_dirty) ->
    vm.note._is_dirty = is_dirty

  # note lists containing only title and guid
  vm.all_notes = {}

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

    # make new note
    noteManager.make_new_note().then(
      (note) =>
        vm.set_guid(note.guid)
        vm.set_title(note.title)
        # activate updating md and html
        vm.set_md_and_update_editor(note.md)
        vm.render_html($('#md_html_div'))
        console.log('New note made: ' + JSON.stringify(note))
      (error) =>
        alert('make_new_note() failed!')
    ).catch (error) => alert('make new note failed!')

    # get note list
    vm.refresh_all_notes()

    # take effect the settings
    vm.set_keyboard_handler(vm.current_keyboard_handler)
    vm.set_show_gutter(vm.current_show_gutter)
    vm.set_ace_theme(vm.current_ace_theme)

    # reset app status
    vm.reset_status()

    # save current note to db periodically
    $interval(vm.save_current_note_to_db, 1000)

    # all ready
    vm.all_ready = true

  # ------------------------------------------------------------------------------------------------------------------
  # ace editor event handlers
  # ------------------------------------------------------------------------------------------------------------------
  vm.editor_content_changed = (event) ->
    # set markdown (single direction updating)
    vm.set_md(vm.ace_editor.getValue())
    # TODO optimize performance
    vm.render_html($('#md_html_div'))

  # ------------------------------------------------------------------------------------------------------------------
  # markdown render functions
  # ------------------------------------------------------------------------------------------------------------------
  vm.render_html = (jq_html_div) ->
    jq_html_div.html($window.marked(vm.get_md()))
    vm.html_post_process(jq_html_div)

  vm.html_post_process = (jq_html_div) ->
    # code highliting
    jq_html_div.find('pre code').each (i, block) ->
      hljs.highlightBlock(block)
    # render Latax
    MathJax.Hub.Queue(['Typeset', MathJax.Hub, jq_html_div.get(0)])
    # change img src to real data url
    jq_html_div.find('img[src]').each (index) ->
      $img = $(this)
      uuid = $img.attr('src')
      imageManager.find_image_by_uuid(uuid).then(
        (image) =>
          if image?
            console.log('change img src from ' + uuid + ' to its base64 content')
            $img.attr('longdesc', uuid)
            $img.attr('src', image.content)
        (error) =>
          alert('vm.html_post_process() failed due to failure in imageManager.find_image_by_uuid(' + uuid + ')')
      )

  # ------------------------------------------------------------------------------------------------------------------
  # Operations for notes
  # ------------------------------------------------------------------------------------------------------------------
  vm.change_current_note = (guid, title, md) ->
    vm.set_guid(guid) if guid?
    vm.set_title(title) if title?
    vm.set_md_and_update_editor(md) if md?
    # render html
    vm.render_html($('#md_html_div'))

  # TODO prevent multiple duplicated requests
  vm.refresh_all_notes = ->
    # TODO handle failure
    noteManager.load_remote_notes().then(
      (notes) ->
        console.log('load_remote_notes() result: ' + JSON.stringify(notes))
        vm.all_notes = notes
      (error) ->
        alert('load_remote_notes() failed: ' + JSON.stringify(error))
    )

  vm.load_note = (guid) ->
    # check if the note to be loaded is already current note
    if guid != vm.get_guid()
      vm.open_loading_modal()
      noteManager.fetch_remote_note(guid).then(
        (note) ->
          # TODO handle other status
          vm.change_current_note(guid=note.guid, title=note.title, md=note.md)
          vm.close_loading_modal()
        (error) ->
          alert('load note ' + guid + ' failed: ' + JSON.stringify(error))
          vm.close_loading_modal()
      )

  vm.save_current_note_to_db = () ->
    if vm.is_note_dirty()
      console.log('current note is dirty, saving to db...')
      note_info =
        guid: vm.get_guid()
        # we don't need to care about title now,
        # because real title will be produced when syncing local notes to remote
        title: vm.get_title()
        md: vm.get_md()
      noteManager.update_note(note_info).then(
        (note) ->
          console.log('dirty note successfully saved to db: ' + JSON.stringify(note) + ', set it to not dirty.')
          vm.set_note_dirty(false)
        (error) ->
          alert('update note failed in save_current_note_to_db(): ' + JSON.stringify(error))
      ).catch (error) => alert('failed to save current note to db!')

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

  # ------------------------------------------------------------------------------------------------------------------
  # save note
  # ------------------------------------------------------------------------------------------------------------------
  vm.save_note = ->
    if vm.saving_note == false
      # set status
      vm.saving_note = true
      # fill the hidden html div
      html_div_hidden = $('#md_html_div_hidden')
      enml = enmlRenderer.getEnmlFromElement(
        html_div_hidden,
        vm.render_html,
        vm.get_md()
      )
      # set title to content of first H1, H2, H3, H4 tag
      vm.note.title = 'New Note - Markever'
      if html_div_hidden.find('h1').size() > 0
        text = html_div_hidden.find('h1').text()
        vm.note.title = text if text.trim().length > 0
      else if html_div_hidden.find('h2').size() > 0
        text = html_div_hidden.find('h2').text()
        vm.note.title = text if text.trim().length > 0
      else if html_div_hidden.find('h3').size() > 0
        text = html_div_hidden.find('h3').text()
        vm.note.title = text if text.trim().length > 0
      else if html_div_hidden.find('p').size() > 0
        text = html_div_hidden.find('p').text()
        vm.note.title = text if text.trim().length > 0
      # invoke the api
      # TODO handle error
      apiClient.notes.save({
          guid: vm.note.guid,
          title: vm.note.title,
          enml: enml,
        }).$promise.then(
          (data) ->
            # update guid
            vm.note.guid = data.note.guid
            # set status back
            vm.saving_note = false
            alert('create/update note succeed: \n' + JSON.stringify(data))
          (error) ->
            # set status back
            vm.saving_note = false
            alert('create note failed: \n' + JSON.stringify(error))
            console.log(JSON.stringify(error))
        )

  # fixme for debug
  vm.note_manager = noteManager
]


# ----------------------------------------------------------------------------------------------------------------------
# Service: enmlRenderer
# ----------------------------------------------------------------------------------------------------------------------
markever.factory 'enmlRenderer', ['imageManager', (imageManager) ->
  getEnmlFromElement = (jq_html_div, html_render_func, markdown) ->
    # init markdown render
    # html post process
    html_render_func(jq_html_div)

    # further post process
    # remove all script tags
    jq_html_div.find('script').remove()

    # set src of img to full data url
    jq_html_div.find('img[src]').attr 'src', (i, src) ->

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
    # FIXME debugging info
    console.log(final_note_xml)
    return final_note_xml

  return {
    getEnmlFromElement : getEnmlFromElement
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
markever.factory 'apiClient', ['$resource', ($resource) ->
  Notes = $resource('/api/v1/notes/:id', {id: '@id'}, {
    all: {method : 'GET', params : {id: ''}},
    note: {method : 'GET', params: {}},
    newest: {method : 'GET', params : {id: 'newest'}},
    save: {method : 'POST', params: {id: ''}},
  })

  return {
    notes : Notes
  }
]

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
    return db.open(db_open_option)

  get_db_server_promise: () =>
    console.log('return @db_server_promise')
    return @db_server_promise

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
['uuid2', 'dbProvider', 'apiClient', 'imageManager',
(uuid2, dbProvider, apiClient, imageManager) -> new class NoteManager

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

  constructor: ->
    dbProvider.get_db_server_promise().then (server) =>
      @db_server = server
      console.log('DB initialized from NoteManager')

  NOTE_STATUS:
    NEW: 0
    SYNCED_META: 1
    SYNCED_ALL: 2
    MODIFIED: 3

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~| Remote Operations >

  # ------------------------------------------------------------
  # Fetch a remote note's all info by guid
  #
  # check if note is in local first
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
        return apiClient.notes.note({id: guid}).$promise.then (data) =>
          _note =
            guid: guid
            title: data.note.title
            md: data.note.md
            status: @NOTE_STATUS.SYNCED_ALL
            resources: data.note.resources
          @update_note(_note)
          return _note

  # ------------------------------------------------------------
  # Load remote note list to update local notes info
  # return: promise
  # ------------------------------------------------------------
  load_remote_notes: =>
    # TODO handle failure
    return apiClient.notes.all().$promise.then (data) =>
      @_merge_remote_notes(data['notes']).then(
        () =>
          console.log('finish merging remote notes')
          return @get_all_notes()
        (error) =>
          # TODO pass error on
          alert('_merge_remote_notes() failed!')
      )

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
        console.log('Merging note [' + guid + ']')

        find_p = @find_note_by_guid(guid).then (note) =>
          _find_p_must_finish_promise_list = []
          if note == null
            console.log('About to add note ' + guid)
            p = @add_note_meta({
              guid: guid
              title: title
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
                })
                _find_p_must_finish_promise_list.push(p)
                console.log('pushed to _find_p_must_finish_promise_list. TAG: B')

              when @NOTE_STATUS.SYNCED_ALL
                # fetch the whole note from server and update local
                console.log('local note ' + guid + ' is SYNCED_ALL, about to fetch from remote for updating')
                @fetch_remote_note(guid).then(
                  (data) =>
                    note =
                      guid: data.note.guid
                      title: data.note.title
                      md: data.note.md
                    p = @update_note(note)
                    # maybe FIXME did not add to promise waiting list
                    #_find_p_must_finish_promise_list.push(p)
                    #console.log('pushed to _find_p_must_finish_promise_list. TAG: C')
                  (error) =>
                    alert('fetch note ' + guid + ' failed during _merge_remote_notes():' + JSON.stringify(error))
                )

              when @NOTE_STATUS.MODIFIED
                # do nothing
                console.log('do nothing')

              else
                alert('IMPOSSIBLE: no correct note status')
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

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~| DB Operations >

  get_all_notes: () =>
    console.log('get_all_notes() invoked')
    return new Promise (resolve, reject) =>
      resolve(@db_server.notes.query().all().execute())

  # ------------------------------------------------------------
  # make a new note to db
  #
  # db_server safe. will get db_server itself
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
              title: 'New Note - Markever'
              md: 'New Note\n==\n'
              status: @NOTE_STATUS.NEW
            })
        resolve(_false_p)
      p = db_server_p.then(
        () =>
          return @find_note_by_guid(guid)
        (error) =>
          alert('make_new_note() error!')
      )
      resolve(p)

  delete_note: (guid) =>
    console.log('delete_note(' + guid + ') invoked')
    return @find_note_by_guid(guid).then(
      (note) =>
        alert('!!')
        if note is null
          console.log('cannot delete note null, aborted')
        else
          console.log('about to remove note id ' + note.id)
          @db_server.notes.remove(note.id)
          console.log('local note ' + note.guid + ' deleted. id: ' + note.id)
      ,(error) =>
        alert('error!')
    )

  # fixme for debug
  add_fake_note: () =>
    @db_server.notes.add({
      guid: '9999-9999-9999-9999'
      title: 'fake title'
      status: @NOTE_STATUS.SYNCED_META
    }).then () ->
      alert('fake note added to db')

  # ------------------------------------------------------------
  # Return a copy of a note in db with a given guid
  # return: promise containing the note's info,
  #         or null if note does not exist
  # ------------------------------------------------------------
  find_note_by_guid: (guid) =>
    # db.js then() does not return a Promise,
    # need to be wrapper in a real Promise
    p = new Promise (resolve, reject) =>
      resolve(@db_server.notes.query().filter('guid', guid).execute())
    return p.then (notes) =>
      if notes.length == 0
        console.log('find_note_by_guid(' + guid + ') returned null')
        return null
      else
        console.log('find_note_by_guid(' + guid + ') hit')
        return notes[0]

  # ------------------------------------------------------------
  # Add a remote note's metadata which is not in local db to db
  #
  # return: promise
  # ------------------------------------------------------------
  add_note_meta: (note) ->
    console.log('Adding note to db - guid: ' + note.guid + ' title: ' + note.title)
    return new Promise (resolve, reject) =>
      resolve(
        @db_server.notes.add({
          guid: note.guid
          title: note.title
          status: @NOTE_STATUS.SYNCED_META
        })
      )

  # ------------------------------------------------------------
  # Update a note
  # return: promise
  # ------------------------------------------------------------
  update_note: (note) =>
    if note.guid? == false
      alert('update_note(): note to be updated must have a guid!')
    console.log('update_note(' + note.guid + ') invoking')
    # register resource data into ImageManager
    if note.resources?
      for r in note.resources
        imageManager.add_image(r.uuid, r.data_url).catch (error) =>
          alert('add image failed! uuid: ' + r.uuid)
        console.log("register uuid: " + r.uuid + " data len: " + r.data_url.length)
    # update notes db
    p = new Promise (resolve, reject) =>
      _note_modify = {}
      if note.title?
        _note_modify.title = note.title
      if note.md?
        _note_modify.md = note.md
      if note.status?
        _note_modify.status = note.status
      resolve(@db_server.notes.query().filter('guid', note.guid).modify(_note_modify).execute())
    return p.then(
      () =>
        console.log('update note ' + note.guid + ' successfully')
        return @find_note_by_guid(note.guid)
      (error) =>
        alert('update note ' + note.guid + ' failed!')
    )

  # ------------------------------------------------------------
  # Clear db
  # return: promise
  # ------------------------------------------------------------
  clear_all_notes: () ->
    return new Promise (resolve, reject) =>
      resolve(@db_server.notes.clear())

  # --------------------------------- tmp operations --------------------------------
]

