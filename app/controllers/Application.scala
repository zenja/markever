package controllers

import play.api._
import play.api.mvc._
import play.twirl.api.Html

object Application extends Controller {

  def index = Action {
    Ok(views.html.index(title="Welcome, zenja!", message="hello world!"))
  }

}