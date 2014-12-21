package controllers

import play.api._
import play.api.mvc._
import play.twirl.api.Html

object Application extends Controller {

  def index = Action { implicit request =>
    // if has auth info, show main page
    if (request.session.get("token").isDefined) {
      Ok(views.html.index())
    } else {
      Redirect(routes.Application.start_oauth())
    }
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
    Redirect(routes.Application.index).withNewSession
  }

}