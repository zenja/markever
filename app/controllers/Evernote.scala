package controllers

import play.api._
import play.api.data.Form
import play.api.data.Forms._
import play.api.libs.oauth._
import play.api.mvc._
import play.api.libs.json._
import play.api.Logger

import com.evernote.thrift.protocol.TBinaryProtocol
import com.evernote.thrift.transport.THttpClient
import com.evernote.thrift.transport.TTransportException

import com.evernote.edam.`type`._
import com.evernote.edam.userstore._
import com.evernote.edam.notestore._

import models.Note
import services.EvernoteHelper

import utils.OAuthConf

import scala.collection.JavaConversions._

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
      val tokenPair = sessionTokenPair(request).get
      // We got the verifier; now get the access token, store it and back to index
      EVERNOTE.retrieveAccessToken(tokenPair, verifier) match {
        case Right(t) => {
          val userStoreTrans: THttpClient = new THttpClient(USER_STORE_URL)
          val userStoreProt: TBinaryProtocol = new TBinaryProtocol(userStoreTrans)
          val userStore: UserStore.Client = new UserStore.Client(userStoreProt, userStoreProt)
          val noteStoreUrl: String = userStore.getNoteStoreUrl(t.token)
          val noteStoreTrans: THttpClient = new THttpClient(noteStoreUrl)
          val noteStoreProt: TBinaryProtocol = new TBinaryProtocol(noteStoreTrans)
          val noteStore: NoteStore.Client = new NoteStore.Client(noteStoreProt, noteStoreProt)
          val notebooks: String = noteStore.listNotebooks(t.token).map(_.getName).mkString(",")
          val evernoteHelper = new EvernoteHelper(t.token)
          // We received the authorized tokens in the OAuth object - store it before we proceed
          Redirect(routes.Application.index).withSession(
            "token" -> t.token,
            "secret" -> t.secret,
            "noteStoreUrl" -> noteStoreUrl,
            "notebooks" -> notebooks
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

  def sessionTokenPair(implicit request: RequestHeader): Option[RequestToken] = {
    for {
      token <- request.session.get("token")
      secret <- request.session.get("secret")
    } yield {
      RequestToken(token, secret)
    }
  }

  val noteForm: Form[Note] = Form {
    mapping(
      "title" -> nonEmptyText,
      "contentXmlStr" -> text
    )(Note.apply)(Note.unapply)
  }

  def createNote = Action { implicit request =>
    val token: Option[String] = request.session.get("token")
    if (token.isDefined) {
      val noteFormData = noteForm.bindFromRequest.get
      val evernoteHelper = new EvernoteHelper(token = token.get)
      try {
        val note = evernoteHelper.createNote(title = noteFormData.title, contentXmlStr = noteFormData.contentXmlStr)
        println("[DEBUG]: request to create note with content: " + noteFormData.contentXmlStr)
        val jsonResult = Json.obj("status" -> "SUCCESS", "note" -> Json.obj("guid" -> note.getGuid), "content" -> note.getContent)
        Created(jsonResult)
      } catch {
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
}
