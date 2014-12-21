package controllers

import play.api._
import play.api.mvc._
import play.twirl.api.Html

object Application extends Controller {

  def index = Action {
    Ok(views.html.index(title="Welcome, zenja!"))
  }

  def start_oauth = Action { implicit request =>
    Ok(views.html.start_oauth()).withSession(request.session)
  }

  def play_evernote = Action { implicit request =>
    Ok(views.html.play_evernote()).withSession(request.session)
  }

  /**
   * Clear session
   */
  def clear = Action { implicit request =>
    Ok(views.html.index(title="Session cleared!")).withNewSession
  }

}