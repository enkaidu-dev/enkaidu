require "file_utils"

module Enkaidu::Env
  # Folder-per-sandbox session.
  abstract class Sandbox
    ROOT   = Path.home / ".local/state/enkaidu"
    FOLDER = ROOT / "sandbox"

    def self.new_path
      FOLDER / generate_id
    end

    private def self.path_for(id : String)
      FOLDER / id
    end

    private def self.exists?(id : String) : Bool
      Dir.exists?(path_for(id))
    end

    # 31 adjectives by 30 nouns is 930 names, and this checks before it
    # returns, so a duplicate is never produced — the old failure mode was
    # running out of *tries*. Twenty tries is comfortable to around 500 stored
    # sessions, deteriorating past 700 and hopeless near 900, which at a few
    # conversations a day is months rather than years. Nothing prunes, so it
    # only ever grows.
    #
    # Hence the fallback: when the two-word space is crowded, number it.
    # Deliberately *only* then — a `-2` never appears until the day it has to,
    # so the first several hundred sessions pay nothing for it, unlike a random
    # suffix that would tax every name from day one against a problem most
    # users will never have. And because the numbering is unbounded, this can
    # no longer fail at all.
    #
    # The real answer for anyone generating sessions in bulk is `--id`, which
    # sidesteps this entirely.
    private def self.generate_id : String
      20.times do
        id = "#{ADJECTIVES.sample}-#{NOUNS.sample}"
        return id unless exists?(id)
      end

      base = "#{ADJECTIVES.sample}-#{NOUNS.sample}"
      suffix = 2
      while exists?("#{base}-#{suffix}")
        suffix += 1
      end
      "#{base}-#{suffix}"
    end

    # Boring on purpose: no adjectives or nouns clever enough to need
    # explaining, easy to say over voice chat, easy to type without a typo.

    ADJECTIVES = %w[
      amber awake blunt brisk calm civic coral crisp
      damp deft dense dull dusty
      eager empty even
      faint firm focal frank fresh
      glib glum gold grand gray
      hardy harsh haste hazy honest
      ideal inert ionic
      jolly joust
      keen
      level linear lively local lucid lunar
      mellow micro mild moist muted
      nimble noble numb
      oval overt oxide
      plain polar prime proud
      quaint quiet
      rapid regal rosy royal rustic
      sharp sheer shiny slack slim smart solar spare split stark steel
      stern stiff sting stoic strong sturdy
      swift
      tally taut tense terra tidal tidy total tough toxic
      unit urban
      valid vast vague vigil vivid vocal void
      wary weary
      yield
      zonal
    ]

    NOUNS = %w[
      apex anode atlas aurora
      beacon belt binary blade blaze
      bolt bore breach
      cache caliber carbon cavern cedar cipher comet core crater
      delta depot depot disk dome
      echo eclipse emitter engine epoch era
      falcon fissure flux forge frame
      galaxy gauge gland gleam glyph
      habitat harbor hatch helix heron hub
      import inlet iris
      jolt junction
      knoll
      lagoon lance layer lens light locus loom lumen lunar lurch
      macro magnet margin mast matrix media meteor metrics module morse
      nebula nectar neon nexus node north nova
      oak obiter ocean orbit
      pact phase phased photon piston pixel planet plate plume pod pole
      qubit quell query
      radar radius rail range rapid raster relay ridge rift rotor route
      sail sample scalar scan scope shard shell shift shore signal silo site
      slate sliver solar source spark spore spring stack state steady stem
      strobe struct summit
      tacit tether tidal tier toggle torch trace tract trail transit
      trunk tube tunnel twine
      umbra unit urban usher
      vale vault vein vendor vent verge vertex vial vigor visual void volt
      warp wavelet wedge weld while whirl wildness wiper wiring wrath wraith
      xerox xenon
      yacht year yield yoke
      zenith zero
    ]
  end
end
