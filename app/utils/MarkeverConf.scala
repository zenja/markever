package utils

import java.io.FileInputStream
import java.util.Properties

object MarkeverConf {
  val (application_tag_name, application_tag_value, application_version) = {
    val prop = new Properties()
    prop.load(new FileInputStream("conf/markever.properties"))
    (
      prop.getProperty("markever.application.tag.name"),
      prop.getProperty("markever.application.tag.value"),
      prop.getProperty("markever.application.version")
      )
  }
}
