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
import com.evernote.edam.`type`.Data
import com.evernote.edam.`type`.Note
import com.evernote.edam.`type`.NoteSortOrder
import com.evernote.edam.`type`.Notebook
import com.evernote.edam.`type`.Resource
import com.evernote.edam.`type`.ResourceAttributes
import com.evernote.edam.`type`.Tag
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

  def allNotes: List[Note] = {
    val allNotes: ListBuffer[Note] = new ListBuffer[Note]
    val notebooks : List[Notebook] = noteStore.listNotebooks().asScala.toList
    for (notebook <- notebooks) {
      val filter = new NoteFilter()
      filter.setNotebookGuid(notebook.getGuid())
      filter.setOrder(NoteSortOrder.CREATED.getValue())
      filter.setAscending(true)

      val noteList : NoteList = noteStore.findNotes(filter, 0, 100)
      val notes : List[Note] = noteList.getNotes().asScala.toList
      for (note <- notes) {
        allNotes.append(note)
      }
    }
    return allNotes.toList
  }

  def createNote(title: String, contentXmlStr: String) : Note = {
    val note = new Note()
    note.setTitle(title)
    note.setContent(contentXmlStr)
    val createdNote: Note = noteStore.createNote(note);
    noteStore.setNoteApplicationDataEntry(createdNote.getGuid(),
      MarkeverConf.application_tag_name,
      MarkeverConf.application_tag_value)
    return createdNote
  }

  // test
  def tryListNotes: Unit = {
    println("all notes:")
    println("-" * 80)
    for (note <- allNotes) {
      println(" * " + note.getTitle)
      println(note.getContent())
    }
    println("-" * 80)
  }

  // test
  def tryCreateNote: Unit = {
    val newNote = createNote(title = "Success!", contentXmlStr = "This note is created by Scala code!")
    println("Successfully created a new note with GUID: " + newNote.getGuid);
    println
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
