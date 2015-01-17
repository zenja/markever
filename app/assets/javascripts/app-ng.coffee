"use strict"

markever = angular.module('markever', ['ngResource', 'ui.bootstrap', 'LocalStorageModule', 'angularUUID2'])

markever.controller 'EditorController',
['$scope', '$window', '$document', '$http', '$sce',
 'localStorageService', 'enmlRenderer', 'scrollSyncor', 'apiClient', 'noteManager', 'imageManager',
($scope, $window, $document, $http, $sce,
 localStorageService, enmlRenderer, scrollSyncor, apiClient, noteManager, imageManager) ->
  vm = this

  # ------------------------------------------------------------------------------------------------------------------
  # Models for notes
  # ------------------------------------------------------------------------------------------------------------------
  # current note
  vm.note =
    guid: ""
    title: ""
    _markdown: ""

  # markdown should only be get from this getter
  vm.get_md = ->
    return vm.note._markdown

  vm.set_md = (md) ->
    vm.note._markdown = md

  vm.set_md_and_update_editor = (md) ->
    vm.note._markdown = md
    vm.ace_editor.setValue(md)

  # note lists containing only title and guid
  vm.all_notes = {}

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

    # get note list
    vm.refresh_all_notes()

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
      data_src = imageManager.get_image_data_from_uuid(uuid)
      if data_src
        $img.attr('longdesc', uuid)
        $img.attr('src', data_src)

  # ------------------------------------------------------------------------------------------------------------------
  # Operations for notes
  # ------------------------------------------------------------------------------------------------------------------
  # TODO prevent multipal duplicated requests
  vm.refresh_all_notes = ->
    # TODO handle failure
    noteManager.load_remote_notes().then (notes) ->
        vm.all_notes = notes

  vm.load_note = (guid) ->
    # check if the note to be loaded is already current note
    if guid != vm.note.guid
      vm.open_loading_modal()
      noteManager.fetch_remote_note(guid).then(
        (note) ->
          # TODO handle other status
          # extract markdown
          md = note.md
          vm.set_md_and_update_editor(md)
          # render html
          vm.render_html($('#md_html_div'))
          # set note info
          vm.note.guid = note.guid
          vm.note.title = note.title
          # close modal
          vm.close_loading_modal()
        (error) ->
          alert('load note ' + guid + ' failed: ' + JSON.stringify(error))
          vm.close_loading_modal()
      )

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
      image_info = imageManager.load_image_blob(blob)
      vm.ace_editor.insert('![Alt text](' + image_info.uuid + ')')

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
# Service: imageManager
# ----------------------------------------------------------------------------------------------------------------------
markever.factory 'imageManager', ['uuid2', (uuid2) -> new class ImageManager
  _image_data_map: {}

  get_image_data_from_uuid: (uuid) =>
    return @_image_data_map[uuid]

  # param data is base64 data url
  add_image_data_mapping: (uuid, data) =>
    @_image_data_map[uuid] = data

  load_image_blob: (blob, extra_handler) =>
    uuid = uuid2.newuuid()
    reader = new FileReader()
    reader.onload = (event) =>
      console.log("image result: " + event.target.result)
      @add_image_data_mapping(uuid, event.target.result)
      # optional extra_handler
      if extra_handler
        extra_handler(event)
    # start reading blob data, and get result in base64 data URL
    reader.readAsDataURL(blob)
    return {
      uuid: uuid
      data: @get_image_data_from_uuid(uuid)
    }
]

# ----------------------------------------------------------------------------------------------------------------------
# Service: noteManager
# ----------------------------------------------------------------------------------------------------------------------
markever.factory 'noteManager', ['apiClient', 'imageManager', (apiClient, imageManager) -> new class NoteManager

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
    @init_db()

  NOTE_STATUS:
    NEW: 0
    SYNCED_META: 1
    SYNCED_ALL: 2
    MODIFIED: 3

  init_db: () =>
    db_open_option = {
      server: 'markever'
      version: 1
      schema: {
        notes: {
          key: { keyPath: 'id' , autoIncrement: true },
          indexes: {
            guid: {}
            title: {}
            status: {}
            md: {}
          }
        }
      }
    }
    db.open(db_open_option).then (server) =>
      @db_server = server
      console.log('DB initiated.')

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
    # fetch remote notes
    # TODO handle failure
    return apiClient.notes.all()
      .$promise.then (data) =>
        @_merge_remote_notes(data['notes'])
        # FIXME need to use promise
        return @get_all_notes()

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~| Merge/Sync Operations >

  # ------------------------------------------------------------
  # merge remote note list into local note list db
  # Possible situations: TODO
  # ------------------------------------------------------------
  _merge_remote_notes: (notes) =>
    # Phase one: patch remote notes to local
    remote_note_guid_list = []
    for note_meta in notes
      remote_note_guid_list.push(note_meta['guid'])
      do (note_meta) =>
        guid = note_meta['guid']
        title = note_meta['title']
        console.log('Merging note [' + guid + ']')

        @find_note_by_guid(guid).then (note) =>
          if note == null
            console.log('About to add note ' + guid)
            @add_note_meta({
              guid: guid
              title: title
            })
          else
            console.log('local note ' + guid + ' exists, updating from remote.')
            switch local_note.status
              when @NOTE_STATUS.NEW
                console.log('[IMPOSSIBLE] remote note\'s local cache is in status NEW')
              when @NOTE_STATUS.SYNCED_META
                # update note title
                @update_note({
                  guid: guid
                  title: title
                })
              when @NOTE_STATUS.SYNCED_ALL
                # fetch the whole note from server and update local
                @fetch_remote_note(guid).then(
                  (data) =>
                    note =
                      guid: data.note.guid
                      title: data.note.title
                      md: data.note.md
                    @update_note(note)
                    # TODO @update_image_manager
                  (error) =>
                    alert('fetch note ' + guid + ' failed during _merge_remote_notess():' + JSON.stringify(error))
                )
              when @NOTE_STATUS.MODIFIED
                # do nothing
                console.log('do nothing')
    # Phase two: deleted local notes not needed
    # Notes that should be deleted:
    # not in remote and status is not new/modified
    @get_all_notes().then (notes) =>
      for n in notes
        if (n.guid not in remote_note_guid_list) && n.status != @NOTE_STATUS.NEW && n.status != @NOTE_STATUS.MODIFIED
          @delete_note(n.guid)

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~| DB Operations >

  get_all_notes: () =>
    return new Promise (resolve, reject) =>
      resolve(@db_server.notes.query().all().execute())

  delete_note: (guid) =>
    console.log('delete_note(' + guid + ') invoked')
    @find_note_by_guid(guid).then(
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
        console.log('find_note_by_guid(' + guid + ') hit: ' + JSON.stringify(notes[0]))
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
  update_note: (note) ->
    console.log('update_note(' + note.guid + ')')
    # register resource data into ImageManager
    if note.resources
      for r in note.resources
        imageManager.add_image_data_mapping(r.uuid, r.data_url)
        console.log("register uuid: " + r.uuid + " data len: " + r.data_url.length)
    # update notes db
    return new Promise (resolve, reject) =>
      resolve(@db_server.notes.query('guid').only(note['guid']).modify(note).execute())

  # ------------------------------------------------------------
  # Clear db
  # return: promise
  # ------------------------------------------------------------
  clear_all_notes: () ->
    return new Promise (resolve, reject) =>
      resolve(@db_server.notes.clear())

  # --------------------------------- tmp operations --------------------------------
]

