package services

// for manual testing
object TryEvernoteService {
  def main(args: Array[String]) = {
    val evernote = new EvernoteHelper("S=s1:U=90105:E=151b4fcef81:C=14a5d4bc370:P=185:A=mwang195:V=2:H=f121681e47d430551b5a942f8315a439")

    // create a note
    val note = evernote.tryCreateNote

    // update the note
//    evernote.updateNote(note.getGuid(), Some("Yo!"), Some(EvernoteHelper.wrapInENML("<div><p>this note is updated!</p></div>")))

    // create a rich note
//    evernote.tryCreateRichNote

    // print all notes' titles
    evernote.tryListMarkeverNotes
  }
}
