package services

import utils.MarkeverConf

import scala.collection.JavaConverters._

import com.evernote.auth.EvernoteAuth
import com.evernote.auth.EvernoteService
import com.evernote.clients.ClientFactory
import com.evernote.clients.NoteStoreClient
import com.evernote.clients.UserStoreClient
import com.evernote.edam.error.EDAMErrorCode
import com.evernote.edam.error.EDAMSystemException
import com.evernote.edam.error.EDAMUserException
import com.evernote.edam.notestore.NoteFilter
import com.evernote.edam.notestore.NoteList
import com.evernote.edam.`type`._
import com.evernote.thrift.transport.TTransportException

import scala.collection.mutable.ListBuffer
import scala.io.Source

// refer to: https://github.com/evernote/evernote-sdk-java/blob/master/sample/client/EDAMDemo.java
class EvernoteHelper(val token: String) {

  // Set up the UserStore client and check that we can speak to the server
  val evernoteAuth = new EvernoteAuth(EvernoteService.SANDBOX, token)
  val factory = new ClientFactory(evernoteAuth)
  val userStore = factory.createUserStoreClient()
  val versionOk = userStore.checkVersion("Markever",
    com.evernote.edam.userstore.Constants.EDAM_VERSION_MAJOR,
    com.evernote.edam.userstore.Constants.EDAM_VERSION_MINOR)
  if (!versionOk) {
    System.err.println("[FATAL] Incompatible Evernote client protocol version. Exit(1).")
    System.exit(1)
  }
  // Set up the NoteStore client
  val noteStore = factory.createNoteStoreClient()

  /** Get all notes created by Markever
    *
    * @return
    */
  def allNotes(retrieveContent: Boolean = false, retrieveResources: Boolean = false): List[Note] = {
    val query = "sourceApplication:" + MarkeverConf.application_identifier
    val noteFilter = new NoteFilter()
    noteFilter.setWords(query)
    noteFilter.setOrder(NoteSortOrder.UPDATED.getValue())
    noteFilter.setAscending(false)
    val noteList : NoteList = noteStore.findNotes(noteFilter, 0, 50)
    // Note objects returned by findNotes() only contain note attributes
    // such as title, GUID, creation date, update date, etc. The note content
    // and binary resource data are omitted, although resource metadata is included.
    // To get the note content and/or binary resources, call getNote() using the note's GUID.
    return if (retrieveContent || retrieveResources) {
      val notes = new ListBuffer[Note]
      val iter = noteList.getNotesIterator
      while (iter.hasNext) {
        val note = iter.next()
        notes.append(noteStore.getNote(note.getGuid, retrieveContent, retrieveResources, false, false))
      }
      notes.toList
    } else {
      noteList.getNotes().asScala.toList
    }
  }

  def createNote(title: String, contentXmlStr: String) : Note = {
    val note = new Note()
    val noteAttribute = new NoteAttributes()
    noteAttribute.setSourceApplication(MarkeverConf.application_identifier)
    note.setTitle(title)
    note.setContent(contentXmlStr)
    note.setAttributes(noteAttribute)
    val createdNote: Note = noteStore.createNote(note);
    return createdNote
  }

  // TODO enrich interface to have notebook guid, tags, resources, etc.
  def updateNote(noteGuid: String, title: Option[String], contentXmlStr: Option[String]) : Note = {
    // check if guid exists
    // TODO handle EDAMNotFoundException, etc.
    val note = if (contentXmlStr.isDefined) {
      noteStore.getNote(noteGuid, false, false, false, false)
    } else {
      noteStore.getNote(noteGuid, true, false, false, false)
    }
    // update content
    if (contentXmlStr.isDefined) {
      note.setContent(contentXmlStr.get)
    } else {
      note.unsetContent()
    }
    // update title
    if (title.isDefined) {
      note.setTitle(title.get)
    }
    noteStore.updateNote(note)
    return note
  }

  // test
  def tryListMarkeverNotes: Unit = {
    println("all notes:")
    println("-" * 80)
    for (note <- allNotes()) {
      println(" * " + note.getTitle)
    }
    println("-" * 80)
  }

  // test
  def tryCreateNote : Note = {
    val contentXmlStr = EvernoteHelper.wrapInENML("<div><p>This note is created by Scala code!</p></div>")
    val newNote = createNote(title = "Success!", contentXmlStr = contentXmlStr)
    println("Successfully created a new note with GUID: " + newNote.getGuid)
    println("Note's source application: " + newNote.getAttributes.getSourceApplication)
    println
    return newNote
  }

  // test
  def tryCreateRichNote: Unit = {
    val rawHtml = Source.fromFile("resources/raw_intro_html.html").getLines.mkString
    val content = "<?xml version='1.0' encoding='utf-8'?>" +
      "<!DOCTYPE en-note SYSTEM 'http://xml.evernote.com/pub/enml2.dtd'>" +
      "<en-note lang=\"v2\" style=\"line-height:1.6;\">" +
      rawHtml.replaceAll("id=\"[^\"]*\"", "")
        .replaceAll("class=\"[^\"]*\"", "")
        .replaceAll("href=\"[^\"]*\"", "")
        .replaceAll("aria-readonly=\"[^\"]*\"", "")
        .replaceAll("</*nobr>", "")
        .replaceAll("<script.*</script>", "")
        .replaceAll("role=\"[^\"]*\"", "") +
      "</en-note>"
    println(content)
    val newNote = createNote(title = "Rich note!", contentXmlStr = content)
    println("Successfully created a new note with GUID: " + newNote.getGuid);
    println
  }
}

object EvernoteHelper {
  def wrapInENML(innerHTML: String) : String = {
    "<?xml version='1.0' encoding='utf-8'?>" +
      "<!DOCTYPE en-note SYSTEM 'http://xml.evernote.com/pub/enml2.dtd'>" +
      s"<en-note>$innerHTML</en-note>"
  }
}
