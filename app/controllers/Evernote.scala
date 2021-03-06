package controllers

import play.api._
import play.api.data.Form
import play.api.data.Forms._
import play.api.libs.oauth._
import play.api.mvc.Security.AuthenticatedBuilder
import play.api.mvc._
import play.api.libs.json._
import play.api.Logger

import com.evernote.thrift.protocol.TBinaryProtocol
import com.evernote.thrift.transport.THttpClient
import com.evernote.thrift.transport.TTransportException

import com.evernote.edam.`type`._
import com.evernote.edam.userstore._
import com.evernote.edam.notestore._

import models.{Note => NoteModel}
import services.EvernoteHelper

import utils.OAuthConf

import scala.collection.JavaConversions._
import scala.collection.mutable.ListBuffer

object Evernote extends Controller {

  val KEY = ConsumerKey(OAuthConf.consumer_key, OAuthConf.consumer_secret)

  val EVERNOTE = OAuth(ServiceInfo(
    OAuthConf.evernote_base_url + "/oauth",
    OAuthConf.evernote_base_url + "/oauth",
    OAuthConf.evernote_base_url + "/OAuth.action", KEY),
    false)

  val CALLBACK_URL = "http://localhost:9000/auth"
  val USER_STORE_URL = OAuthConf.evernote_base_url + "/edam/user"

  def authenticate = Action { request =>
    request.queryString.get("oauth_verifier").flatMap(_.headOption).map { verifier =>
      // TODO can get always success? can it be None?
      val tokenPair = sessionTokenPair(request).get
      // We got the verifier; now get the access token, store it and back to index
      EVERNOTE.retrieveAccessToken(tokenPair, verifier) match {
        case Right(t) => {
          // We received the authorized tokens in the OAuth object - store it before we proceed
          Redirect(routes.Application.index).withSession(
            "token" -> t.token,
            "secret" -> t.secret
          )
        }
        case Left(e) => throw e
      }
    }.getOrElse(
        EVERNOTE.retrieveRequestToken(CALLBACK_URL) match {
          case Right(t) => {
            // We received the unauthorized tokens in the OAuth object - store it before we proceed
            Redirect(EVERNOTE.redirectUrl(t.token)).withSession("token" -> t.token, "secret" -> t.secret)
          }
          case Left(e) => throw e
        })
  }

  /**
   * Helper function
   *
   * @param request
   * @return
   */
  def sessionTokenPair(implicit request: RequestHeader): Option[RequestToken] = {
    for {
      token <- request.session.get("token")
      secret <- request.session.get("secret")
    } yield {
      RequestToken(token, secret)
    }
  }

  val noteForm: Form[NoteModel] = Form {
    mapping(
      // guid is option: when creating new note guid is not needed
      "guid" -> text,
      "notebookGuid" -> text,
      "title" -> nonEmptyText,
      "enml" -> nonEmptyText
    )(NoteModel.apply)(NoteModel.unapply)
  }

  def updateNote = Action { implicit request =>
    if (tokenExists(request.session)) {
      val token: String = request.session.get("token").get
      val noteFormData = noteForm.bindFromRequest.get
      val evernoteHelper = new EvernoteHelper(token = token)
      try {
        val note = evernoteHelper.updateNote(
          guid = noteFormData.guid,
          notebookGuid = noteFormData.notebookGuid,
          title = noteFormData.title,
          enmlNotTransformed = noteFormData.enml
        )
        val jsonResult = Json.obj(
          "status" -> "SUCCESS",
          "note" -> Json.obj("guid" -> note.getGuid, "notebook_guid" -> note.getNotebookGuid)
        )
        Created(jsonResult)
      } catch {
        // TODO handle other exceptions
        case ex: Throwable => {
          // return error message
          val jsonResult = Json.obj("status" -> "ERROR", "msg" -> ("Failed to create the note: " + ex.toString))
          InternalServerError(jsonResult)
        }
      }
    } else {
      // token info missing, re-auth required
      val jsonResult = Json.obj("status" -> "AUTH_REQUIRED")
      Forbidden(jsonResult)
    }
  }

  def allNotes = Action { implicit request =>
    if (tokenExists(request.session)) {
      val token: String = request.session.get("token").get
      val evernoteHelper = new EvernoteHelper(token = token)
      try {
        val notes = evernoteHelper.allNotes()
        var notesJsonArr = Json.arr()
        for (note <- notes) {
          // FIXME avoid creating lots of new obj
          notesJsonArr = notesJsonArr.append(Json.obj(
            "title" -> note.getTitle,
            "guid" -> note.getGuid,
            "notebook_guid" -> note.getNotebookGuid)
          )
        }
        val jsonResult = Json.obj("status" -> "SUCCESS", "notes" -> notesJsonArr)
        Ok(jsonResult)
      } catch {
        // TODO handle other exceptions
        case ex: Throwable => {
          // return error message
          val jsonResult = Json.obj("status" -> "ERROR", "msg" -> ("Failed to get all notes: " + ex.toString))
          InternalServerError(jsonResult)
        }
      }
    } else {
      // token info missing, re-auth required
      val jsonResult = Json.obj("status" -> "AUTH_REQUIRED")
      Forbidden(jsonResult)
    }
  }

  def getNote(guid: String) = Action { implicit request =>
    if (tokenExists(request.session)) {
      val token: String = request.session.get("token").get
      val evernoteHelper = new EvernoteHelper(token = token)
      try {
        val note: Option[Note] = evernoteHelper.getNote(guid = guid, retrieveContent = true, retrieveResources = true)
        note match {
          case Some(n) => {
            // make resources data
            val resourceInfoList = new ListBuffer[JsObject]
            if (n.getResources != null) {
              for (r <- n.getResources) {
                val uuid = EvernoteHelper.getUUID(r)
                val dataURL = EvernoteHelper.makeDataURL(r)
                resourceInfoList.append(Json.obj("uuid" -> uuid, "data_url" -> dataURL))
              }
            }
            val jsonResult = Json.obj(
              "status" -> "SUCCESS",
              "note" -> Json.obj(
                "guid" -> n.getGuid,
                "notebook_guid" -> n.getNotebookGuid,
                "title" -> n.getTitle,
                "md" -> EvernoteHelper.getMarkdownInENML(n.getContent),
                "resources" -> JsArray(resourceInfoList)
              )
            )
            Ok(jsonResult)
          }
          case None => NotFound(Json.obj("status" -> "NO_NOTE"))
        }
      } catch {
        // TODO handle other exceptions
        case ex: Throwable => {
          // return error message
          val jsonResult = Json.obj("status" -> "ERROR", "msg" -> ("Failed to fetch the note: " + ex.toString))
          InternalServerError(jsonResult)
        }
      }
    } else {
      // token info missing, re-auth required
      val jsonResult = Json.obj("status" -> "AUTH_REQUIRED")
      Forbidden(jsonResult)
    }
  }

  def newestNote = Action { implicit request =>
    if (tokenExists(request.session)) {
      val token: String = request.session.get("token").get
      val evernoteHelper = new EvernoteHelper(token = token)
      try {
        val note = evernoteHelper.newestNote(retrieveContent = true)
        note match {
          case Some(n) => {
            val jsonResult = Json.obj("status" -> "SUCCESS",
              "note" -> Json.obj(
                "title" -> n.getTitle,
                "guid" -> n.getGuid,
                "enml" -> n.getContent
              )
            )
            Ok(jsonResult)
          }
          case None => {
            val jsonResult = Json.obj("status" -> "NO_NOTE")
            NotFound(jsonResult)
          }
        }
      } catch {
        // TODO handle other exceptions
        case ex: Throwable => {
          // return error message
          val jsonResult = Json.obj("status" -> "ERROR", "msg" -> ("Failed to fetch the newest note: " + ex.toString))
          InternalServerError(jsonResult)
        }
      }
    } else {
      // token info missing, re-auth required
      val jsonResult = Json.obj("status" -> "AUTH_REQUIRED")
      Forbidden(jsonResult)
    }
  }

  def allNotebooks = Action { implicit request =>
    if (tokenExists(request.session)) {
      val token: String = request.session.get("token").get
      val evernoteHelper = new EvernoteHelper(token = token)
      try {
        val notebooks : List[Notebook] = evernoteHelper.allNotebooks()
        var notebooksJsonArr = Json.arr()
        for (nb <- notebooks) {
          // FIXME avoid creating lots of new obj
          notebooksJsonArr = notebooksJsonArr.append(Json.obj("name" -> nb.getName, "guid" -> nb.getGuid))
        }
        val jsonResult = Json.obj("status" -> "SUCCESS", "notebooks" -> notebooksJsonArr)
        Ok(jsonResult)
      } catch {
        // TODO handle other exceptions
        case ex: Throwable => {
          // return error message
          val jsonResult = Json.obj("status" -> "ERROR", "msg" -> ("Failed to get all notebooks: " + ex.toString))
          InternalServerError(jsonResult)
        }
      }
    } else {
      // token info missing, re-auth required
      val jsonResult = Json.obj("status" -> "AUTH_REQUIRED")
      Forbidden(jsonResult)
    }
  }

  /**
   * Helper function: check if Evernote auth info exists
   */
  def tokenExists(session: Session): Boolean = {
    val token: Option[String] = session.get("token")
    token.isDefined
  }
}
