import Foundation

/// Welche Menuepunkte einer App ins Dock-Menue der Leiste kommen.
///
/// Apples Dock zeigt dort, was die App selbst anbietet (bei Vivaldi "Neues
/// Fenster", "Neues privates Fenster"). Dieses Dock-Menue der App liegt nur
/// Apples Dock offen. Dieselben Befehle stehen aber in ihrer Menueleiste,
/// im ersten Menue nach dem App-Menue (File/Ablage, bei kitty "Shell") -
/// gemessen 14.09. bei Vivaldi, kitty, ForkLift. Uebernommen wird, was mit
/// "New"/"Neu" beginnt und gerade anwaehlbar ist.
public enum DockCommandFilter {
    public static func isNewCommand(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("New ") || trimmed.hasPrefix("Neu")
    }
}
