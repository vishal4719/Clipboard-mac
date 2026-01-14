import Foundation
import Combine

struct EmojiCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String // System icon name for the category
    let emojis: [String]
}

class EmojiManager: ObservableObject {
    static let shared = EmojiManager()
    
    @Published var categories: [EmojiCategory] = []
    
    private init() {
        setupCategories()
    }
    
    private func setupCategories() {
        categories = [
            EmojiCategory(name: "Smileys", icon: "face.smiling", emojis: [
                "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "🥲", "☺️",
                "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗",
                "😙", "😚", "😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓",
                "😎", "🥸", "🤩", "🥳", "😏", "😒", "😞", "😔", "ww", "💩",
                "👻", "💀", "☠️", "👽", "👾", "🤖", "🎃", "😺", "😸", "😹"
            ]),
            EmojiCategory(name: "Hand Signs", icon: "hand.thumbsup", emojis: [
                "👍", "👎", "👊", "✊", "🤛", "🤜", "🤞", "✌️", "🤟", "🤘",
                "👌", "🤌", "🤏", "👈", "👉", "👆", "👇", "☝️", "✋", "🤚",
                "🖐", "🖖", "👋", "🤙", "💪", "🦾", "🖕", "✍️", "🙏", "🦶"
            ]),
            EmojiCategory(name: "Animals", icon: "hare", emojis: [
                "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐻‍❄️", "🐨",
                "🐯", "🦁", "🐮", "🐷", "🐽", "🐸", "🐵", "🙈", "🙉", "🙊",
                "🐒", "🐔", "🐧", "🐦", "🐤", "🐣", "🐥", "🦆", "🦅", "🦉"
            ]),
            EmojiCategory(name: "Food", icon: "fork.knife", emojis: [
                "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐",
                "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🍆", "🥑",
                "🥦", "🥬", "🥒", "🌶", "🫑", "🌽", "🥕", "🫒", "🧄", "🧅"
            ]),
            EmojiCategory(name: "Hearts", icon: "heart.fill", emojis: [
                "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔",
                "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "☮️"
            ])
        ]
    }
}
