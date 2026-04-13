import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    @State private var conversation: ChatConversation?

    let suggestedQuestions = [
        "Como estão meus gastos este mês?",
        "Qual foi meu maior gasto?",
        "Resumo financeiro do mês",
        "Quanto posso gastar até o fim do mês?",
        "Quando vence minha fatura?"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    suggestionsView
                } else {
                    chatScrollView
                }

                inputBar
            }
            .navigationTitle("Chat IA")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { clearChat() } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var suggestionsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Pergunte sobre suas finanças")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(suggestedQuestions, id: \.self) { question in
                        Button {
                            inputText = question
                            sendMessage()
                        } label: {
                            Text(question)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }
                    if isLoading {
                        TypingIndicatorView()
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Digite sua pergunta...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""

        isLoading = true

        // Sprint 4: substituir por chamada real à AIService
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let response = ChatMessage(
                role: .assistant,
                content: "Esta funcionalidade estará disponível após configurar sua chave de API nas Configurações. Acesse Configurações → IA para adicionar sua chave OpenAI ou Anthropic."
            )
            messages.append(response)
            isLoading = false
        }
    }

    private func clearChat() {
        messages = []
        inputText = ""
    }
}

// MARK: - Chat Bubble

struct ChatBubbleView: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                Image(systemName: "sparkles.square.filled.on.square")
                    .font(.title3)
                    .foregroundStyle(.purple)
                    .frame(width: 32, height: 32)
            }

            Text(message.content)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var animate = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "sparkles.square.filled.on.square")
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animate ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                            value: animate
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer(minLength: 60)
        }
        .onAppear { animate = true }
    }
}
