package local.curated.phone

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Biotech
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Brush
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Celebration
import androidx.compose.material.icons.filled.Checkroom
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.EmojiEmotions
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Extension
import androidx.compose.material.icons.filled.FamilyRestroom
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.Grass
import androidx.compose.material.icons.filled.Handyman
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.LocalCafe
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.LocalHospital
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MedicalServices
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MonetizationOn
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Park
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.PhoneIphone
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.SportsBasketball
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.SportsFootball
import androidx.compose.material.icons.filled.Stadium
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.WbCloudy
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.WineBar
import androidx.compose.material.icons.filled.Work
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * The Material icon closest to a category's SF Symbol: the Mac's choices (`Category.symbolChoices` in its Models.swift).
 * Anything else is a folder, the Mac's default.
 */
fun categoryGlyph(symbol: String?): ImageVector = when (symbol) {
    "star" -> Icons.Filled.Star
    "heart" -> Icons.Filled.Favorite
    "sparkles" -> Icons.Filled.AutoAwesome
    "flame" -> Icons.Filled.LocalFireDepartment
    "bolt" -> Icons.Filled.Bolt
    "crown" -> Icons.Filled.WorkspacePremium
    "trophy" -> Icons.Filled.EmojiEvents
    "newspaper" -> Icons.Filled.Newspaper
    "globe.americas" -> Icons.Filled.Public
    "building.columns" -> Icons.Filled.AccountBalance
    "flag" -> Icons.Filled.Flag
    "megaphone" -> Icons.Filled.Campaign
    "mic" -> Icons.Filled.Mic
    "quote.bubble" -> Icons.Filled.FormatQuote
    "bubble.left.and.bubble.right" -> Icons.Filled.Forum
    "person.2" -> Icons.Filled.People
    "figure.2.and.child.holdinghands" -> Icons.Filled.FamilyRestroom
    "face.smiling" -> Icons.Filled.EmojiEmotions
    "theatermasks" -> Icons.Filled.TheaterComedy
    "party.popper" -> Icons.Filled.Celebration
    "gamecontroller" -> Icons.Filled.SportsEsports
    "puzzlepiece" -> Icons.Filled.Extension
    "film" -> Icons.Filled.Movie
    "tv" -> Icons.Filled.Tv
    "music.note" -> Icons.Filled.MusicNote
    "guitars" -> Icons.Filled.LibraryMusic
    "headphones" -> Icons.Filled.Headphones
    "camera" -> Icons.Filled.PhotoCamera
    "paintpalette" -> Icons.Filled.Palette
    "paintbrush" -> Icons.Filled.Brush
    "book" -> Icons.AutoMirrored.Filled.MenuBook
    "graduationcap" -> Icons.Filled.School
    "lightbulb" -> Icons.Filled.Lightbulb
    "brain.head.profile" -> Icons.Filled.Psychology
    "atom" -> Icons.Filled.Science
    "flask" -> Icons.Filled.Biotech
    "cpu" -> Icons.Filled.Memory
    "desktopcomputer" -> Icons.Filled.Computer
    "iphone" -> Icons.Filled.PhoneIphone
    "wrench.and.screwdriver" -> Icons.Filled.Build
    "hammer" -> Icons.Filled.Handyman
    "car" -> Icons.Filled.DirectionsCar
    "airplane" -> Icons.Filled.Flight
    "map" -> Icons.Filled.Map
    "sportscourt" -> Icons.Filled.Stadium
    "football" -> Icons.Filled.SportsFootball
    "basketball" -> Icons.Filled.SportsBasketball
    "figure.run" -> Icons.AutoMirrored.Filled.DirectionsRun
    "dumbbell" -> Icons.Filled.FitnessCenter
    "bicycle" -> Icons.AutoMirrored.Filled.DirectionsBike
    "fork.knife" -> Icons.Filled.Restaurant
    "cup.and.saucer" -> Icons.Filled.LocalCafe
    "wineglass" -> Icons.Filled.WineBar
    "carrot" -> Icons.Filled.Grass
    "leaf" -> Icons.Filled.Eco
    "pawprint" -> Icons.Filled.Pets
    "tree" -> Icons.Filled.Park
    "mountain.2" -> Icons.Filled.Terrain
    "sun.max" -> Icons.Filled.WbSunny
    "moon" -> Icons.Filled.DarkMode
    "cloud.sun" -> Icons.Filled.WbCloudy
    "house" -> Icons.Filled.Home
    "briefcase" -> Icons.Filled.Work
    "dollarsign.circle" -> Icons.Filled.MonetizationOn
    "chart.line.uptrend.xyaxis" -> Icons.AutoMirrored.Filled.TrendingUp
    "cart" -> Icons.Filled.ShoppingCart
    "bag" -> Icons.Filled.ShoppingBag
    "tshirt" -> Icons.Filled.Checkroom
    "stethoscope" -> Icons.Filled.MedicalServices
    "cross.case" -> Icons.Filled.LocalHospital
    "gift" -> Icons.Filled.CardGiftcard
    else -> Icons.Filled.Folder
}
