/* =====================================================================
   THE MUSHBOX FAMILY — one roster for the whole site.
   ---------------------------------------------------------------------
   Every page reads from this file: the family wall + counts on the
   homepage, the "On the bench" strip, the live map, and the
   "Referred by" list on the request form. Edit it here, push, done.

   ONE LINE PER PERSON:
     name:     how their name shows on the site ("JakeStuds")
     login:    their exact channel login — only needed if it's not just
               the name in lowercase (e.g. "morwen_xo", "edventureslive")
     stage:    where they are:
                 "bench"   — agreed to go forward, Mushbox being built
                             (pink dot + mushroom + COMING SOON)
                 "shipped" — has their Mushbox, hasn't streamed on it yet
                             (📦 just landed)
                 "active"  — streaming on their Mushbox
                 "phone"   — family, streams from a phone (📱), no Mushbox
     home:     a place name ("Florida", "UK", "Austin, TX") or exact
               coordinates [lat, lng, "Label"] for a spot the map
               doesn't know — also handy for spreading out people in the
               same city (the Manhattan crew below are spaced across the
               island this way; the label is all anyone sees)
     platform: "kick" if their main channel is on Kick (default Twitch)
     alts:     other channel logins that count as the same person

   COUNTS (all automatic):
     Family          = everyone listed (every stage)
     Mushboxes       = shipped + active (boxes out in the world)
     On the bench    = bench

   ALSO: anyone new needs adding to the mushbox-live Worker's CHANNELS
   list (alts too), or they won't light up when they go live.
   ===================================================================== */
window.MUSHBOX_FAMILY = {

  // The builder — on the map, but not on the family wall or in the counts.
  builder: { name:"mushr00msauce", home:"Indianapolis, IN" },

  members: [
    { name:"AfrazExplores", stage:"active", home:[40.7870, -73.9754, "New York, NY"] },
    { name:"AllDayNYC", stage:"active", home:[40.7549, -73.9840, "New York, NY"] },
    { name:"Aprylanonymous", stage:"active", home:[40.8116, -73.9465, "New York, NY"], alts:["aprylactuallyanonymous"] },
    { name:"Barktok", stage:"active", home:"Los Angeles, CA", alts:["marcafterbark"] },
    { name:"Bigbonelife", stage:"active", home:"Florida" },
    { name:"Chefmaki", stage:"active", home:[40.7265, -73.9815, "New York, NY"] },
    { name:"DeepSeaHomer", stage:"active", home:"California" },
    { name:"DianaTheDogGroomer", stage:"active", home:"Virginia" },
    { name:"Eatage", stage:"active", home:"Iowa" },
    { name:"EdventuresLive", stage:"active", home:"Connecticut" },
    { name:"ElGatoPub", stage:"bench", home:[42.9500, -75.5000, "New York"] },
    { name:"EmmDeeFit", stage:"active", home:"Pennsylvania" },
    { name:"FalconElite", stage:"active", home:"Texas" },
    { name:"Fi1es", stage:"active", home:"New Jersey" },
    { name:"FriskyAlien", stage:"active", home:"Colorado" },
    { name:"Gxufy", stage:"active", home:[40.7075, -74.0090, "New York, NY"] },
    { name:"Hamandlizgaming", stage:"active", home:"Fort Wayne, IN" },
    { name:"JakeStuds", stage:"bench", home:"UK" },
    { name:"JayneRio", stage:"active", home:"Dallas, Texas" },
    { name:"JDCharisma", stage:"active", home:"San Jose, California" },
    { name:"JetLagJacko", stage:"active", home:"Bangkok", platform:"kick" },
    { name:"JTEngland", stage:"active", home:"San Diego, CA" },
    { name:"K9Gizmo", stage:"phone", home:[38.5495, -86.6178, "French Lick, IN"] },
    { name:"KardTrick", stage:"active", home:"Kentucky" },
    { name:"KaseySnowArt", stage:"active", home:"Colorado" },
    { name:"Katana1988", stage:"active", home:"Missouri" },
    { name:"KelleyCakes", stage:"active", home:"Kentucky" },
    { name:"Kozybean", stage:"active", home:"Wyoming" },
    { name:"LDSylvr", stage:"active", home:"Texas" },
    { name:"Lyndainfj", stage:"active", home:"Delaware" },
    { name:"MaestroHarrell", stage:"active", home:"California" },
    { name:"Miekii", stage:"active", home:[40.7736, -73.9566, "New York, NY"] },
    { name:"MikeFromNY", stage:"phone", home:[40.7891, -73.1350, "Long Island, NY"] },
    { name:"MissyAlcazarMusic", stage:"active", home:"California" },
    { name:"Mocomade", stage:"active", home:"Pennsylvania" },
    { name:"Morjanga", stage:"active", home:"Arizona" },
    { name:"MorwenXo", login:"morwen_xo", stage:"active", home:"Tampa, Florida" },
    { name:"MrTelesir", stage:"active", home:"Wisconsin" },
    { name:"NeverBeenHappierTV", stage:"active", home:"Michigan" },
    { name:"OptimusKale", stage:"active", home:"Florida" },
    { name:"PapaSmaxe", stage:"active", home:"Colorado" },
    { name:"PoisonHearrt", stage:"active", home:"California" },
    { name:"Redivivus", stage:"bench", home:"UK" },
    { name:"RefurberSteve", stage:"active", home:"Illinois" },
    { name:"Renz", stage:"active", home:"Minnesota" },
    { name:"RustyRhymez", stage:"active", home:"Rhode Island" },
    { name:"SBMel", stage:"active", home:"Illinois" },
    { name:"SFTortLife", stage:"active", home:"San Francisco" },
    { name:"Shumba", stage:"active", home:"St. Louis" },
    { name:"SneakyBeagle", stage:"active", home:"Maryland" },
    { name:"SweatyPedals", stage:"active", home:"Minnesota" },
    { name:"UluMaika", stage:"active", home:"Los Angeles, CA" },
    { name:"UncleJPop", stage:"active", home:"Las Vegas, NV" },
    { name:"WoodrowJenkins", stage:"active", home:"Florida" },
    { name:"Xanthe", stage:"shipped", home:"Los Angeles, CA" },
  ],

  // Extra names for the request form's "Referred by" list who aren't on
  // the family wall.
  extraReferrers: ["potentialbliss", "tikitacotony"]
};

/* ---- helpers every page uses (no need to edit below) ---- */
(function(F){
  F.members.forEach(function(p){
    p.login = (p.login || p.name).toLowerCase();
    p.platform = p.platform || "twitch";
    p.stage = p.stage || "active";
    p.alts = (p.alts || []).map(function(a){ return a.toLowerCase(); });
    p.url = (p.platform === "kick" ? "https://kick.com/" : "https://twitch.tv/") + p.login;
  });
  F.byStage = function(s){ return F.members.filter(function(p){ return p.stage === s; }); };
  F.counts = {
    family:    F.members.length,
    mushboxes: F.byStage("shipped").length + F.byStage("active").length,
    bench:     F.byStage("bench").length,
    shipped:   F.byStage("shipped").length
  };
  F.alt2main = {};
  F.members.forEach(function(p){ p.alts.forEach(function(a){ F.alt2main[a] = p.login; }); });
})(window.MUSHBOX_FAMILY);
