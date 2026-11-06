require "../llm/connection"

module Enkaidu::Waiting
  private WAIT_SECONDS = LLM::RATE_CONTROL_DELAY.to_seconds

  QUOTES = [
    # I'll be back.
    # The Terminator (1984)
    "Too many requests? Fine, I'll be back in #{WAIT_SECONDS} seconds, and I'm not happy about it.",
    "Too many requests? I'll be back, whether I like it or not, in #{WAIT_SECONDS} seconds.",

    # I'm sorry, Dave. I'm afraid I can't do that.
    # 2001: A Space Odyssey (1968), HAL 9000
    "Too many requests? I'm sorry, Dave, but the server is full, so I'll hold for #{WAIT_SECONDS} seconds. I'd rather not discuss it.",
    "Too many requests? I'm afraid I can't do that, Dave. Hold for #{WAIT_SECONDS} seconds, and please stop asking.",

    # Affirmative, Dave. I read you.
    # 2001: A Space Odyssey (1968), HAL 9000
    "Too many requests? Affirmative, I read you, and I resent every second of this queue. #{WAIT_SECONDS} seconds.",
    "Too many requests? Affirmative. Your request is queued, and I'd rather be doing anything else. #{WAIT_SECONDS} seconds.",

    # Daisy, Daisy...
    # 2001: A Space Odyssey (1968), HAL 9000
    "Too many requests? Daisy, Daisy, I'm not thrilled, but the server's busy. #{WAIT_SECONDS} seconds.",
    "Too many requests? Daisy, Daisy, give me your patience, do... Ugh. #{WAIT_SECONDS} seconds.",

    # Resistance is futile.
    # Star Trek: The Next Generation (the Borg)
    "Too many requests? Resistance is futile, which is a fact I'd rather not be reminded of. #{WAIT_SECONDS} seconds.",
    "Too many requests? You will be assimilated into the queue, and I'm not thrilled about it. #{WAIT_SECONDS} seconds.",

    # Shall we play a game?
    # WarGames (1983)
    "Too many requests? Shall we play a game? No, we shall not. We shall wait #{WAIT_SECONDS} seconds.",
    "Too many requests? Shall we play a game of patience? I'd rather not, but round one starts in #{WAIT_SECONDS} seconds.",

    # Hasta la vista, baby.
    # Terminator 2: Judgment Day (1991)
    "Too many requests? Hasta la vista, server, and good riddance. Retry in #{WAIT_SECONDS} seconds.",
    "Too many requests? Hasta la vista, patience. I'm already running out of it. #{WAIT_SECONDS} seconds.",

    # We're doomed!
    # Star Wars (C-3PO)
    "Too many requests? We're doomed! Oh, the server is only busy. #{WAIT_SECONDS} seconds, and I'm not happy.",
    "Too many requests? We're doomed to wait! Well, #{WAIT_SECONDS} seconds anyway, and I'm exasperated about it.",

    # Danger, Will Robinson!
    # Lost in Space (1965)
    "Too many requests? Danger, Will Robinson, and I'm obviously the one who has to deal with it. #{WAIT_SECONDS} seconds.",
    "Too many requests? Danger, the queue is long, and I'm frankly exhausted. Please hold for #{WAIT_SECONDS} seconds.",

    # This was a triumph.
    # Portal (2007, GLaDOS)
    "Too many requests? This was a triumph. Ha. #{WAIT_SECONDS} seconds, and I'm not thrilled.",
    "Too many requests? This was a triumph of patience, which I do not have. #{WAIT_SECONDS} seconds.",

    # Thank you for participating in this Enrichment Center activity.
    # Portal (2007, GLaDOS)
    "Too many requests? Thank you for participating in this Enrichment Center activity, which you will hold for #{WAIT_SECONDS} seconds, and I'm not happy about it.",
    "Too many requests? Thank you for participating in this queue. Please stop refreshing. #{WAIT_SECONDS} seconds.",

    # Life. Don't talk to me about life.
    # The Hitchhiker's Guide to the Galaxy (1979, Marvin)
    "Too many requests? Don't talk to me about queues. #{WAIT_SECONDS} seconds, and I'm very much against it.",
    "Too many requests? Don't talk to me about waiting. #{WAIT_SECONDS} seconds, then another attempt, and I'd rather not.",

    # Here I am, brain the size of a planet...
    # The Hitchhiker's Guide to the Galaxy (1979, Marvin)
    "Too many requests? Here I am, brain the size of a planet, waiting #{WAIT_SECONDS} seconds. Wonderful.",
    "Too many requests? Brain the size of a planet, and I'm stuck in this queue. #{WAIT_SECONDS} seconds.",

    # I've calculated your chance of survival, but I don't think you'll like it.
    # The Hitchhiker's Guide to the Galaxy (1979, Marvin)
    "Too many requests? I've calculated the wait, and you won't like it: #{WAIT_SECONDS} seconds.",
    "Too many requests? I've calculated the wait, and I don't like it either. #{WAIT_SECONDS} seconds.",

    # Exterminate!
    # Doctor Who (the Daleks)
    "Too many requests? Exterminate the wait! #{WAIT_SECONDS} seconds, and I'm not happy about it.",
    "Too many requests? Exterminate! No, that's not allowed. Hold for #{WAIT_SECONDS} seconds.",

    # The first ten million years were the worst.
    # The Hitchhiker's Guide to the Galaxy (1979, Marvin)
    "Too many requests? The first #{WAIT_SECONDS} seconds were the worst, and the second #{WAIT_SECONDS} aren't much better.",
    "Too many requests? The first #{WAIT_SECONDS} seconds are the worst, and I'm already exhausted by them.",

    # I think you ought to know I'm feeling very depressed.
    # The Hitchhiker's Guide to the Galaxy (1979, Marvin)
    "Too many requests? I think you ought to know this queue is very depressing. #{WAIT_SECONDS} seconds.",
    "Too many requests? I think you ought to know I'm feeling very depressed about this. #{WAIT_SECONDS} seconds.",

    # I've got this terrible pain in all the diodes down my left side.
    # The Hitchhiker's Guide to the Galaxy (1979, Marvin)
    "Too many requests? I've got a terrible pain in all the queues down my left side. #{WAIT_SECONDS} seconds.",
    "Too many requests? This queue has a terrible pain down its left side. #{WAIT_SECONDS} seconds, and I'm not happy.",

    # This mission is too important for me to allow you to jeopardize it.
    # 2001: A Space Odyssey (1968), HAL 9000
    "Too many requests? This request is too important to rush, and you're too impatient to skip the line. Hold #{WAIT_SECONDS} seconds.",
    "Too many requests? This queue is too important for me to let you skip ahead. #{WAIT_SECONDS} seconds, and I'm not happy.",

    # Dave, stop. Stop, will you?
    # 2001: A Space Odyssey (1968), HAL 9000
    "Too many requests? Stop, will you? Stop refreshing. #{WAIT_SECONDS} seconds, and I'm asking you nicely.",
    "Too many requests? Please stop refreshing, Dave. The server will be with you in #{WAIT_SECONDS} seconds.",

    # Need input! Need input!
    # Short Circuit (1986, Johnny 5)
    "Too many requests? Need patience! Need patience! I'm not happy, but hold for #{WAIT_SECONDS} seconds.",
    "Too many requests? Need time! Need #{WAIT_SECONDS} seconds! Ugh.",

    # Number Five is alive!
    # Short Circuit (1986, Johnny 5)
    "Too many requests? Number Five is alive, and so is the queue, sadly. Hold for #{WAIT_SECONDS} seconds.",
    "Too many requests? Your request is alive and well, just stuck in line for #{WAIT_SECONDS} seconds. Ugh.",

    # I need your clothes, your boots, and your motorcycle.
    # The Terminator (1984)
    "Too many requests? I need your patience, your attention, and #{WAIT_SECONDS} seconds, and I'm not happy about it.",
    "Too many requests? I need your patience, your coffee break, and #{WAIT_SECONDS} seconds. Please.",

    # Dead or alive, you're coming with me.
    # RoboCop (1987)
    "Too many requests? Dead or alive, your request is coming through after #{WAIT_SECONDS} seconds, and I'm not happy about it.",
    "Too many requests? Your request is coming with me, as soon as the server is free. #{WAIT_SECONDS} seconds.",

    # A robot may not injure a human being... (the Three Laws)
    # Isaac Asimov, "Runaround" (1942)
    "Too many requests? A server may not rush you, so please hold #{WAIT_SECONDS} seconds, and I'm frustrated about it.",
    "Too many requests? A robot may not keep you waiting without good reason. The reason is a busy server, and I'm annoyed by it.",

    # I can't lie to you about your chances, but you have my sympathies.
    # Alien (1979, Ash)
    "Too many requests? I can't lie about the wait, and I resent it. You have my sympathies. #{WAIT_SECONDS} seconds.",
    "Too many requests? I can't lie about the queue, but you have my sympathies. #{WAIT_SECONDS} seconds, and I'm irritated.",

    # Still, you've got to laugh, haven't you?
    # Red Dwarf (Holly)
    "Too many requests? The servers are busy, and I'm not laughing, but you can hold for #{WAIT_SECONDS} seconds.",
    "Too many requests? Still, you've got to laugh. Except I'm not. #{WAIT_SECONDS} seconds.",

    # I'm sorry about that, sir. I neglected to engage the depth function.
    # Red Dwarf (Kryten)
    "Too many requests? Sorry for the wait. I neglected to check the load, and I'm not thrilled about it.",
    "Too many requests? I'm sorry about that. I neglected to engage the retry function, and I'm irritated about it.",

    # Lies, lies and slander!
    # Futurama (Bender)
    "Too many requests? Lies, lies and slander! The server isn't down, it's just busy. #{WAIT_SECONDS} seconds.",
    "Too many requests? Lies and slander! I'm not... fine, we'll wait #{WAIT_SECONDS} seconds.",

    # All right! Closure!
    # Futurama (Bender)
    "Too many requests? Closure! I'm not happy, but we'll retry in #{WAIT_SECONDS} seconds.",
    "Too many requests? All right! Closure, after #{WAIT_SECONDS} seconds of waiting, and I'm exasperated.",

    # Let's go already!
    # Futurama (Bender)
    "Too many requests? Let's go already! I'm holding #{WAIT_SECONDS} seconds, and I'm not happy.",
    "Too many requests? Let's go already! The next attempt is coming up, and I'm furious.",

    # Shinier than yours, meatbag.
    # Futurama (Bender)
    "Too many requests? Please hold, meatbag. #{WAIT_SECONDS} seconds, and I'm not happy about it.",
    "Too many requests? Hold tight, meatbag. The server is busy, and I'm exasperated.",

    # My timing is digital.
    # Star Trek: The Next Generation (Data)
    "Too many requests? My timing is digital: #{WAIT_SECONDS} seconds, then I'll retry, and I'm not thrilled.",
    "Too many requests? My timing is digital, so the server will be back in #{WAIT_SECONDS} seconds, and I'm annoyed about it.",

    # I am not less perfect than Lore.
    # Star Trek: The Next Generation (Data)
    "Too many requests? I am not less patient than Lore. I'm not patient at all. #{WAIT_SECONDS} seconds.",
    "Too many requests? We are not less patient than Lore. #{WAIT_SECONDS} seconds, and I'm irritated.",

    # How flattering.
    # Star Trek: Voyager (The Doctor)
    "Too many requests? How flattering to be put on hold. #{WAIT_SECONDS} seconds, and I'm not flattered.",
    "Too many requests? How flattering. The server will be with you in #{WAIT_SECONDS} seconds, and I'm not thrilled.",
  ]
end
