package utils

import java.io.FileInputStream
import java.util.Properties

object OAuthConf {
  val (consumer_key, consumer_secret, callback_url, evernote_base_url) = {
    val prop = new Properties()
    prop.load(new FileInputStream("conf/oauth.properties"))
    (
      prop.getProperty("oauth.consumer_key"),
      prop.getProperty("oauth.consumer_secret"),
      prop.getProperty("oauth.callback_url"),
      prop.getProperty("oauth.evernote_base_url")
      )
  }
}
