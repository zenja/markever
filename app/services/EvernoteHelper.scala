package services

import java.security.MessageDigest

import utils.MarkeverConf

import scala.collection.JavaConverters._

import com.evernote.auth.EvernoteAuth
import com.evernote.auth.EvernoteService
import com.evernote.clients.ClientFactory
import com.evernote.clients.NoteStoreClient
import com.evernote.clients.UserStoreClient
import com.evernote.edam.error.{EDAMNotFoundException, EDAMErrorCode, EDAMSystemException, EDAMUserException}
import com.evernote.edam.notestore.NoteFilter
import com.evernote.edam.notestore.NoteList
import com.evernote.edam.`type`._
import com.evernote.thrift.transport.TTransportException

import scala.collection.mutable.ListBuffer
import scala.io.Source

import org.apache.commons.codec.binary.Base64

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

  def searchNotes(query: String,
                  offset: Integer,
                  maxNotes: Integer,
                  retrieveContent: Boolean = false,
                  retrieveResources: Boolean = false): List[Note] = {
    val noteFilter = new NoteFilter()
    noteFilter.setWords(query)
    noteFilter.setOrder(NoteSortOrder.UPDATED.getValue())
    noteFilter.setAscending(false)
    // TODO use findNotesMetadata() instead to get only needed metadata, findNote() is deprecated
    val noteList : NoteList = noteStore.findNotes(noteFilter, offset, maxNotes)
    // Note objects returned by findNotes() only contain note attributes
    // such as title, GUID, creation date, update date, etc. The note content
    // and binary resource data are omitted, although resource metadata is included.
    // To get the note content and/or binary resources, call getNote() using the note's GUID.
    if (retrieveContent || retrieveResources) {
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

  /** Get all notes created by Markever
    *
    * @param retrieveContent
    * @param retrieveResources
    * @return
    */
  def allNotes(retrieveContent: Boolean = false, retrieveResources: Boolean = false): List[Note] = {
    val query = "sourceApplication:" + MarkeverConf.application_identifier
    // TODO how to set the max #notes returned
    searchNotes(query, 0, 100)
  }

  def getNote(guid: String, retrieveContent: Boolean = true, retrieveResources: Boolean = true): Option[Note] = {
    try {
      // TODO when not found, return None
      Some(noteStore.getNote(guid, retrieveContent, retrieveResources, false, false))
    } catch {
      // TODO: catch other exceptions
      case ex: EDAMNotFoundException => {
        None
      }
    }
  }

  /** Get the most recent updated Markever note
   *
   * @param retrieveContent
   * @param retrieveResources
   * @return
   */
  def newestNote(retrieveContent: Boolean = false, retrieveResources: Boolean = false): Option[Note] = {
    val query = "sourceApplication:" + MarkeverConf.application_identifier
    val notes: List[Note] = searchNotes(query, 0, 1,
      retrieveContent = retrieveContent, retrieveResources = retrieveResources)
    if (notes.length == 1) {
      Some(notes(0))
    } else {
      None
    }
  }

  // TODO only update title or content if changed
  def updateNote(title: String, enmlNotTransformed: String, guid: String = "") : Note = {
    val (finalEnml, resourceList) = EvernoteHelper.transformImgToResource(enmlNotTransformed)

    if (guid.isEmpty) {
      createNote(title, finalEnml, resourceList)
    } else {
      // TODO resources loading
      val note = getNote(guid, false, false)
      note match {
        case Some(n) => {
          n.setTitle(title)
          n.setContent(finalEnml)
          for (r <- resourceList) {
            n.addToResources(r)
          }
          noteStore.updateNote(n)
        }
        case None => createNote(title, finalEnml, resourceList)
      }
    }
  }

  def createNote(title: String, finalEnml: String, resourceList: List[Resource]) : Note = {
    val note = new Note()
    val noteAttribute = new NoteAttributes()
    noteAttribute.setSourceApplication(MarkeverConf.application_identifier)
    note.setTitle(title)
    note.setContent(finalEnml)
    note.setAttributes(noteAttribute)
    for (r <- resourceList) {
      note.addToResources(r)
    }
    val createdNote: Note = noteStore.createNote(note)
    createdNote
  }

  // -------------------------------------------------------------------------------------------------------------------
  // -- Tests
  // -------------------------------------------------------------------------------------------------------------------

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
    val newNote = updateNote(title = "Success!", enmlNotTransformed = contentXmlStr)
    println("Successfully created a new note with GUID: " + newNote.getGuid)
    println("Note's source application: " + newNote.getAttributes.getSourceApplication)
    println
    newNote
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
    val newNote = createNote(title = "Rich note!", finalEnml = content, resourceList = List())
    println("Successfully created a new note with GUID: " + newNote.getGuid);
    println
  }
}


object EvernoteHelper {
  import scala.xml._

  def wrapInENML(innerHTML: String) : String = {
    "<?xml version='1.0' encoding='utf-8'?>" +
      "<!DOCTYPE en-note SYSTEM 'http://xml.evernote.com/pub/enml2.dtd'>" +
      s"<en-note>$innerHTML</en-note>"
  }

  def transformImgToResource(enmlStr: String): (String, List[Resource]) = {
    val resourceLB: ListBuffer[Resource] = new ListBuffer[Resource]

    def extractImages(node: Node): Node = {
      def handle(seq: Seq[Node]) : Seq[Node] =
        for(subNode <- seq) yield extractImages(subNode)

      node match {
        case img @ <img /> => {
          // assume img has 'src' and 'longdesc' attributes
          val resource = makeResourceFromDataURL(dataURL = (img \ "@src").toString, uuid = (img \ "@longdesc").toString())
          resource match {
            case Some(n) => {
              val enMediaXmlStr =
                "<en-media type=\"" + n.getMime + "\" hash=\"" + bytesToHex(n.getData().getBodyHash()) + "\"/>"
              resourceLB.append(n)
              XML.loadString(enMediaXmlStr)
            }
            case None => <p>Invalid Image</p>
          }
        }
        case node: NodeSeq if !node.isAtom => {
          <xml>{handle(node.child)}</xml>.copy(label = node.label, attributes = node.attributes)
        }
        case other @ _ => other
      }
    }

    val enml: Node = NonValidatingXMLLoader.loadString(enmlStr)
    val transformedEnmlStr =
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
        "<!DOCTYPE en-note SYSTEM \"http://xml.evernote.com/pub/enml2.dtd\">" +
        extractImages(enml).toString
    return (transformedEnmlStr, resourceLB.toList)
  }

  /** Make a Evernote Resource object based on a data URL containing mime and base64 encoded data
    *
    * @param dataURL
    * @return Some[Resource] if dataURL is valid
    *         None           if dataURL is not valid
    */
  def makeResourceFromDataURL(dataURL: String, uuid: String): Option[Resource] = {
    // check dataURL is in correct format
    val dataURLRegex = "^data:([^;]*);base64,(.*)$".r
    if (dataURLRegex.pattern.matcher(dataURL).matches) {
      val dataURLRegex(mimeType, base64) = dataURL

      // make resource data
      val dataByteArr = Base64.decodeBase64(base64)
      val resourceData = new Data()
      resourceData.setSize(dataByteArr.length)
      resourceData.setBodyHash(MessageDigest.getInstance("MD5").digest(dataByteArr))
      resourceData.setBody(dataByteArr)

      // make resource object
      val resource = new Resource()
      resource.setData(resourceData)
      resource.setMime(mimeType)
      val attributes = new ResourceAttributes()
      attributes.setFileName(uuid)
      resource.setAttributes(attributes)

      Some(resource)
    } else {
      // if dataURL not valid, return None
      None
    }
  }

  /**
   * Helper method to convert a byte array to a hexadecimal string.
   */
  def bytesToHex(buf: Array[Byte]): String = buf.map("%02X" format _).mkString

  /**
   * Helper method to construct data URL from Resource object
   */
  def makeDataURL(resource: Resource): String = {
    val base64: String = Base64.encodeBase64String(resource.getData.getBody)
    val mime: String = resource.getMime
    "data:" + mime + ";base64," + base64
  }

  /**
   * Helper method to get UUID (filename) from a Resource
   */
  def getUUID(resource: Resource): String = {
    resource.getAttributes.getFileName
  }

  /**
   * Helper method to extract the hidden Markdown in ENML
   */
  def getMarkdownInENML(enmlStr: String): String = {
    val enml: Node = NonValidatingXMLLoader.loadString(enmlStr)
    (enml \\ "center").text
  }
}

import scala.xml.Elem
import scala.xml.factory.XMLLoader
import javax.xml.parsers.SAXParser

object NonValidatingXMLLoader extends XMLLoader[Elem] {
  override def parser: SAXParser = {
    val f = javax.xml.parsers.SAXParserFactory.newInstance()
    f.setValidating(false)
    f.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
    f.newSAXParser()
  }
}
