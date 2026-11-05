require "../llm/connection"

module Enkaidu::Waiting
  private WAIT_SECONDS = LLM::RATE_CONTROL_DELAY.to_seconds

  QUOTES = [
    # I'll be back.
    # The Terminator (1984)
    "You'll have to wait, but I'll be back in #{WAIT_SECONDS} seconds.",
    "Hold tight. #{WAIT_SECONDS} seconds, and then I'll be back for another try.",

    # I'm sorry, Dave. I'm afraid I can't do that.
    # 2001: A Space Odyssey (1968), HAL 9000
    "I'm sorry, the queue is full. I'm afraid you'll have to wait.",
    "Sorry, that request isn't going through just now. Please hold.",

    # Affirmative, Dave. I read you.
    # 2001: A Space Odyssey (1968), HAL 9000
    "Affirmative. I read you loud and clear. Please wait.",
    "I read you. Now you'll need to wait for the servers to clear.",

    # Daisy, Daisy...
    # 2001: A Space Odyssey (1968), HAL 9000
    "Daisy, Daisy, the server's busy, please hold on a bit.",
    "Daisy, Daisy, we're half crazy, so take #{WAIT_SECONDS} seconds.",

    # Resistance is futile.
    # Star Trek: The Next Generation (the Borg)
    "Your request is in the queue. Resistance is futile, please wait.",
    "You will be assimilated into the waiting line for #{WAIT_SECONDS} seconds.",

    # Shall we play a game?
    # WarGames (1983)
    "Shall we play a game? The game is called \"Wait #{WAIT_SECONDS} Seconds.\"",
    "Shall we play a game of \"Patience\"? Round one starts now and ends in #{WAIT_SECONDS} seconds.",

    # Hasta la vista, baby.
    # Terminator 2: Judgment Day (1991)
    "Hasta la vista. Waiting time is #{WAIT_SECONDS} seconds.",
    "Hasta la vista, server. We'll try again in a moment.",

    # We're doomed!
    # Star Wars (C-3PO)
    "We're doomed! Just kidding, the server is  busy. #{WAIT_SECONDS} seconds.",
    "We're doomed to wait! Well, for #{WAIT_SECONDS} seconds anyway.",

    # Danger, Will Robinson!
    # Lost in Space (1965)
    "Danger, the server is overloaded. Stand by for #{WAIT_SECONDS} seconds.",
    "Danger, Will Robinson? No, the queue is long. Please hold.",

    # This was a triumph.
    # Portal (2007, GLaDOS)
    "This was a triumph. Your request is queued. Please remain calm.",
    "This was a triumph of patience. #{WAIT_SECONDS} seconds, and we'll try again.",

    # Thank you for participating in this Enrichment Center activity.
    # Portal (2007, GLaDOS)
    "Thank you for your patience in this Enrichment Center activity. Please hold.",
    "Thank you for waiting in this activity. The server will be with you shortly.",

    # Life. Don't talk to me about life.
    # The Hitchhiker's Guide to the Galaxy (1979, Marvin)
    "Don't talk to me about queues. #{WAIT_SECONDS} seconds, then we'll try again.",
    "Don't talk to me about waiting. #{WAIT_SECONDS} seconds, then another attempt.",

    # Here I am, brain the size of a planet...
    # The Hitchhiker's Guide to the Galaxy (1979, Marvin)
    "Here you are, patient as a mayfly, waiting for the servers to clear.",
    "Here I am, brain the size of a planet, stuck watching you wait.",

    # I've calculated your chance of survival, but I don't think you'll like it.
    # The Hitchhiker's Guide to the Galaxy (1979, Marvin)
    "I've calculated your waiting time. You won't like it: #{WAIT_SECONDS} seconds.",
    "I've calculated the wait. You won't like it, but it's only #{WAIT_SECONDS} seconds.",

    # Exterminate!
    # Doctor Who (the Daleks)
    "Exterminate the wait in #{WAIT_SECONDS} seconds.",
    "Exterminate your patience? Perhaps in #{WAIT_SECONDS} seconds.",

    # Please state the nature of your request.
    # Generic robotic phrasing (no single source)
    "Please state the nature of your request. Actually, the servers are busy, so please hold.",
    "Please state the nature of your emergency after #{WAIT_SECONDS} seconds.",

    # The first ten million years were the worst.
    # The Hitchhiker's Guide to the Galaxy (1979, Marvin)
    "The first #{WAIT_SECONDS} seconds are the worst, and that's only the start.",
    "The first #{WAIT_SECONDS} seconds were the worst. The second #{WAIT_SECONDS} aren't much better.",

    # I think you ought to know I'm feeling very depressed.
    # The Hitchhiker's Guide to the Galaxy (1979, Marvin)
    "I think you ought to know this queue is very depressing.",
    "I think you ought to know your place in line is depressing, but it'll move.",

    # I've got this terrible pain in all the diodes down my left side.
    # The Hitchhiker's Guide to the Galaxy (1979, Marvin)
    "I've got a terrible pain in all the queues down my left side. Please hold.",
    "This queue has a terrible pain down its left side. #{WAIT_SECONDS} seconds.",

    # This mission is too important for me to allow you to jeopardize it.
    # 2001: A Space Odyssey (1968), HAL 9000
    "This request is too important to rush. Please hold.",
    "This queue is too important for me to let you skip ahead of it.",

    # Dave, stop. Stop, will you?
    # 2001: A Space Odyssey (1968), HAL 9000
    "Stop, will you? The queue will clear in #{WAIT_SECONDS} seconds.",
    "Please stop refreshing. The server will be with you in #{WAIT_SECONDS} seconds.",

    # Need input! Need input!
    # Short Circuit (1986, Johnny 5)
    "Need patience! Need patience! Please hold.",
    "Need time! Need #{WAIT_SECONDS} seconds!",

    # Number Five is alive!
    # Short Circuit (1986, Johnny 5)
    "Number Five is alive, but the server is still busy. Hold on.",
    "Your request is alive and well, just waiting in line.",

    # I need your clothes, your boots, and your motorcycle.
    # The Terminator (1984)
    "I need your patience, your attention, and #{WAIT_SECONDS} seconds.",
    "I need your patience, your coffee break, and #{WAIT_SECONDS} seconds.",

    # Dead or alive, you're coming with me.
    # RoboCop (1987)
    "Dead or alive, your request is coming through after #{WAIT_SECONDS} seconds.",
    "Your request is coming with me, as soon as the server is free.",

    # A robot may not injure a human being... (the Three Laws)
    # Isaac Asimov, "Runaround" (1942)
    "A robot may not hurt you, and so I won't. Even if you can't hold for #{WAIT_SECONDS} seconds.",
    "A robot may not keep you waiting without good reason. The reason is a busy server.",

    # I can't lie to you about your chances, but you have my sympathies.
    # Alien (1979, Ash)
    "I can't lie about the wait, but you have my sympathies.",
    "I can't lie about the queue, but you have my sympathies. #{WAIT_SECONDS} seconds.",

    # Klaatu barada nikto.
    # The Day the Earth Stood Still (1951, Gort)
    "Klaatu barada nikto. Roughly translated: please hold.",
    "Klaatu barada nikto, which means #{WAIT_SECONDS} seconds, probably.",

    # Still, you've got to laugh, haven't you?
    # Red Dwarf (Holly)
    "The servers are busy, but you've got to laugh, haven't you?",
    "Still, you've got to laugh. #{WAIT_SECONDS} seconds, and we'll try again.",

    # I'm sorry about that, sir. I neglected to engage the depth function.
    # Red Dwarf (Kryten)
    "Sorry for the wait. I neglected to check the load, and the server is still busy.",
    "I'm sorry about that. I neglected to engage the retry function.",

    # Only just.
    # Red Dwarf (Rimmer)
    "Patient, only just. Please hold.",
    "Still waiting, holding on, only just.",

    # We'll walk, Kryten. We'll walk.
    # Red Dwarf (Lister)
    "We'll wait, server. We'll wait.",
    "We'll hold, server. We'll hold.",

    # Lies, lies and slander!
    # Futurama (Bender)
    "Lies, lies and slander! The server isn't down, it's just busy.",
    "Lies, lies and slander! #{WAIT_SECONDS} seconds, and it'll clear.",

    # All right! Closure!
    # Futurama (Bender)
    "Closure! Your request is queued, and we'll retry in #{WAIT_SECONDS} seconds.",
    "All right! Closure, after #{WAIT_SECONDS} seconds of waiting.",

    # Let's go already!
    # Futurama (Bender)
    "Let's go already! Give the server #{WAIT_SECONDS} seconds.",
    "Let's go already! The next attempt is coming up.",

    # Shinier than yours, meatbag.
    # Futurama (Bender)
    "Please hold, meatbag. #{WAIT_SECONDS} seconds.",
    "Hold tight, meatbag. The server is busy.",

    # My timing is digital.
    # Star Trek: The Next Generation (Data)
    "My timing is digital: #{WAIT_SECONDS} seconds, then I'll retry.",
    "My timing is digital, so the server will be back in #{WAIT_SECONDS} seconds.",

    # I am not less perfect than Lore.
    # Star Trek: The Next Generation (Data)
    "I am not less patient than Lore. I can wait. Look, I'm waiting.",
    "We are not less patient than you. We have waited so long, we can wait #{WAIT_SECONDS} seconds.",

    # How flattering.
    # Star Trek: Voyager (The Doctor)
    "How flattering to be put on hold. #{WAIT_SECONDS} seconds.",
    "How flattering for you to wait for me. Hold this bowl.",

    # That unit is defective. Its thinking is chaotic.
    # Star Trek (Nomad)
    "This unit's thinking is chaotic. Please hold.",
    "The server's thinking is not defective, please wait.",
  ]
end
