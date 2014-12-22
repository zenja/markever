package utils

import java.io.FileInputStream
import java.util.Properties

object MarkeverConf {
  val (application_identifier, application_version) = {
    val prop = new Properties()
    prop.load(new FileInputStream("conf/markever.properties"))
    (
      prop.getProperty("markever.application.identifier"),
      prop.getProperty("markever.application.version")
      )
  }
}
