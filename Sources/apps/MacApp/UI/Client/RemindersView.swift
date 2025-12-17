import ClientService
import SwiftUI

struct RemindersView: View {
    var apiClient: APIClient
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reminders: [Reminder] = []
    @State private var showingAddReminder = false
    @State private var editingReminder: Reminder?

    var body: some View {
        VStack(spacing: 12) {
            // Toolbar
            HStack {
                Button(action: {
                    showingAddReminder = true
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
                .help("Add Reminder")

                Spacer()

                Button(action: {
                    Task {
                        await loadReminders()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Divider()

            // Reminders List
            if reminders.isEmpty && !isLoading {
                Text("No reminders yet")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(reminders) { reminder in
                    ReminderRowView(
                        reminder: reminder,
                        onToggleComplete: {
                            Task {
                                await toggleComplete(reminder)
                            }
                        },
                        onEdit: {
                            editingReminder = reminder
                        },
                        onDelete: {
                            Task {
                                await deleteReminder(reminder)
                            }
                        }
                    )
                }
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingAddReminder) {
            ReminderFormView(apiClient: apiClient, mode: .add) { _ in
                Task {
                    await loadReminders()
                }
            }
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderFormView(apiClient: apiClient, mode: .edit(reminder)) { _ in
                Task {
                    await loadReminders()
                }
            }
        }
        .task {
            await loadReminders()
        }
    }

    private func loadReminders() async {
        isLoading = true
        errorMessage = nil

        do {
            reminders = try await apiClient.listReminders()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func toggleComplete(_ reminder: Reminder) async {
        isLoading = true
        errorMessage = nil

        do {
            _ = try await apiClient.updateReminder(id: reminder.id, isComplete: !reminder.isComplete)
            await loadReminders()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func deleteReminder(_ reminder: Reminder) async {
        isLoading = true
        errorMessage = nil

        do {
            try await apiClient.deleteReminder(id: reminder.id)
            await loadReminders()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct ReminderRowView: View {
    let reminder: Reminder
    let onToggleComplete: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggleComplete) {
                Image(systemName: reminder.isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(reminder.isComplete ? .green : .secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.name)
                    .strikethrough(reminder.isComplete)
                    .foregroundColor(reminder.isComplete ? .secondary : .primary)
                    .lineLimit(1)

                if let details = reminder.details, !details.isEmpty {
                    Text(details)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let dueDate = reminder.dueDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(dueDate, style: .date)
                            .font(.caption2)
                    }
                    .foregroundColor(isOverdue(dueDate) && !reminder.isComplete ? .red : .secondary)
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button(reminder.isComplete ? "Mark Incomplete" : "Mark Complete") {
                onToggleComplete()
            }
            Button("Edit") {
                onEdit()
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }

    private func isOverdue(_ date: Date) -> Bool {
        date < Date()
    }
}

struct ReminderFormView: View {
    let apiClient: APIClient
    let mode: ReminderFormMode
    let onSave: (Reminder) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var details: String = ""
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()
    @State private var isComplete: Bool = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum ReminderFormMode {
        case add
        case edit(Reminder)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditMode ? "Edit Reminder" : "New Reminder")
                .font(.headline)

            Form {
                TextField("Name", text: $name)

                TextField("Details (optional)", text: $details)

                Toggle("Has Due Date", isOn: $hasDueDate)

                if hasDueDate {
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date])
                }

                if isEditMode {
                    Toggle("Complete", isOn: $isComplete)
                }
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button(isEditMode ? "Save" : "Add") {
                    Task {
                        await saveReminder()
                    }
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty || isLoading)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            if case .edit(let reminder) = mode {
                name = reminder.name
                details = reminder.details ?? ""
                hasDueDate = reminder.dueDate != nil
                dueDate = reminder.dueDate ?? Date()
                isComplete = reminder.isComplete
            }
        }
    }

    private var isEditMode: Bool {
        if case .edit = mode {
            return true
        }
        return false
    }

    private func saveReminder() async {
        isLoading = true
        errorMessage = nil

        do {
            let reminder: Reminder
            let finalDueDate = hasDueDate ? dueDate : nil
            let finalDetails = details.isEmpty ? nil : details

            switch mode {
            case .add:
                reminder = try await apiClient.createReminder(
                    name: name,
                    details: finalDetails,
                    dueDate: finalDueDate
                )
            case .edit(let existing):
                reminder = try await apiClient.updateReminder(
                    id: existing.id,
                    name: name,
                    details: finalDetails,
                    dueDate: finalDueDate,
                    isComplete: isComplete
                )
            }

            onSave(reminder)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    RemindersView(apiClient: .preview)
}
