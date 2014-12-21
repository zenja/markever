package services

/**
 * Created by xing on 12/18/14.
 */
object TryEvernoteService {
  def main(args: Array[String]) = {
    val evernote = new EvernoteHelper("S=s1:U=90105:E=151b4fcef81:C=14a5d4bc370:P=185:A=mwang195:V=2:H=f121681e47d430551b5a942f8315a439")

    // create a note
//    evernote.tryCreateNote

    // create a rich note
//    evernote.tryCreateRichNote

    // print all notes' titles
    evernote.tryListNotes

  }
}
