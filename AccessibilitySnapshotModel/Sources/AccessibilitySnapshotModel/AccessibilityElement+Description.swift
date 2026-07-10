import Foundation

extension AccessibilityElement {
    /// Assembles the VoiceOver-style description and hint for this element from its stored properties,
    /// the container `context` derived from its position in the graph, and a verbosity configuration.
    ///
    /// This is the un-baked replacement for parse-time `NSObject.accessibilityDescription(context:)`:
    /// it reads only model data (label/value/traits/hint/language/customContent + `DerivedContext`),
    /// so it runs on any platform and can be recomputed at any verbosity. At `.verbose` (the default)
    /// it reproduces the historical description byte-for-byte.
    public func description(
        context: DerivedContext?,
        verbosity: VerbosityConfiguration = .verbose
    ) -> (description: String, hint: String?) {
        let strings = Strings(locale: accessibilityLanguage)

        var accessibilityDescription = hidesAccessibilityLabel(backDescriptor: strings.backDescriptor)
            ? ""
            : (label ?? "")

        var hintDescription = hint?.nonEmpty()

        let numberFormatter = NumberFormatter()
        if let localeIdentifier = accessibilityLanguage {
            numberFormatter.locale = Locale(identifier: localeIdentifier)
        }

        let descriptionContainsContext: Bool
        if verbosity.includesTableContext,
           case let .dataTableCell(row, column, width, height, isFirstInRow, rowHeaders, columnHeaders) = context
        {
            let headersDescription = (rowHeaders + columnHeaders).map { header -> String in
                switch (header.label?.nonEmpty(), header.value?.nonEmpty()) {
                case (nil, nil):
                    return ""
                case let (.some(label), nil):
                    return "\(label). "
                case let (nil, .some(value)):
                    return "\(value). "
                case let (.some(label), .some(value)):
                    return "\(label): \(value). "
                }
            }.reduce("", +)

            let trailingPeriod = accessibilityDescription.hasSuffix(".") ? "" : "."

            let showsHeight = (height > 1 && row != NSNotFound)
            let showsWidth = (width > 1 && column != NSNotFound)
            let showsRow = (isFirstInRow && row != NSNotFound)
            let showsColumn = (column != NSNotFound)

            accessibilityDescription =
                headersDescription
                    + accessibilityDescription
                    + trailingPeriod
                    + (showsHeight ? " " + String(format: strings.dataTableRowSpanFormat, numberFormatter.string(from: .init(value: height))!) : "")
                    + (showsWidth ? " " + String(format: strings.dataTableColumnSpanFormat, numberFormatter.string(from: .init(value: width))!) : "")
                    + (showsRow ? " " + String(format: strings.dataTableRowFormat, numberFormatter.string(from: .init(value: row + 1))!) : "")
                    + (showsColumn ? " " + String(format: strings.dataTableColumnFormat, numberFormatter.string(from: .init(value: column + 1))!) : "")

            descriptionContainsContext = true
        } else {
            descriptionContainsContext = false
        }

        if verbosity.includesValue,
           let value = value?.nonEmpty(),
           !hidesAccessibilityValue
        {
            if let existingDescription = accessibilityDescription.nonEmpty() {
                if descriptionContainsContext {
                    accessibilityDescription += " \(value)"
                } else {
                    accessibilityDescription = "\(existingDescription): \(value)"
                }
            } else {
                accessibilityDescription = value
            }
        }

        if verbosity.includesCustomContent {
            for content in customContent where content.isImportant {
                let contentDescription = content.value.isEmpty ? content.label : content.value
                if let existingDescription = accessibilityDescription.nonEmpty() {
                    accessibilityDescription = "\(existingDescription), \(contentDescription)"
                } else {
                    accessibilityDescription = contentDescription
                }
            }
        }

        if traits.contains(.selected) {
            if let existingDescription = accessibilityDescription.nonEmpty() {
                accessibilityDescription = String(format: strings.selectedTraitFormat, existingDescription)
            } else {
                accessibilityDescription = strings.selectedTraitName
            }
        }

        var traitSpecifiers: [String] = []
        let shouldIncludeTraits = verbosity.includesTraits && verbosity.traitPosition != .none

        if shouldIncludeTraits {
            if traits.contains(.notEnabled) {
                traitSpecifiers.append(strings.notEnabledTraitName)
            }

            let hidesButtonTraitInContext = context?.hidesButtonTrait ?? false
            let hidesButtonTraitFromTraits = [AccessibilityTraits.keyboardKey, .switchButton, .tabBarItem, .backButton].contains(where: { traits.contains($0) })
            if traits.contains(.button) && !hidesButtonTraitFromTraits && !hidesButtonTraitInContext {
                traitSpecifiers.append(strings.buttonTraitName)
            }

            if traits.contains(.backButton) {
                traitSpecifiers.append(strings.backButtonTraitName)
            }

            if traits.contains(.switchButton) {
                if traits.contains(.button) {
                    // An element can have the private switch button trait without being a UISwitch (for example, by passing
                    // through the traits of a contained switch). In this case, VoiceOver will still read the "Switch
                    // Button." trait, but only if the element's traits also include the `.button` trait.
                    traitSpecifiers.append(strings.switchButtonTraitName)
                }

                switch value {
                case "1":
                    traitSpecifiers.append(strings.switchButtonOnStateName)
                case "0":
                    traitSpecifiers.append(strings.switchButtonOffStateName)
                case "2":
                    traitSpecifiers.append(strings.switchButtonMixedStateName)
                default:
                    // Prior to iOS 17 the then private trait would suppress any other accessibility values.
                    // Once the trait became public in 17 values other than the above are announced with the trait specifiers.
                    if let value {
                        traitSpecifiers.append(value)
                    }
                }
            }

            let showsTabTraitInContext = context?.showsTabTrait ?? false
            if traits.contains(.tabBarItem) || showsTabTraitInContext {
                traitSpecifiers.append(strings.tabTraitName)
            }

            if traits.contains(.textEntry) {
                if traits.contains(.secureTextField) {
                    traitSpecifiers.append(strings.secureTextFieldTraitName)
                } else {
                    traitSpecifiers.append(strings.textEntryTraitName)
                }

                if traits.contains(.isEditing) {
                    traitSpecifiers.append(strings.isEditingTraitName)
                }
            }

            if traits.contains(.header) {
                traitSpecifiers.append(strings.headerTraitName)
            }

            if traits.contains(.link) {
                traitSpecifiers.append(strings.linkTraitName)
            }

            if traits.contains(.adjustable) {
                traitSpecifiers.append(strings.adjustableTraitName)
            }

            if traits.contains(.image) {
                traitSpecifiers.append(strings.imageTraitName)
            }

            if traits.contains(.searchField) {
                traitSpecifiers.append(strings.searchFieldTraitName)
            }
        }

        // If the description is empty, use the hint as the description.
        if accessibilityDescription.isEmpty {
            accessibilityDescription = hintDescription ?? ""
            hintDescription = nil
        }

        // Add trait specifiers to description based on position preference.
        if !traitSpecifiers.isEmpty {
            let joinedTraits = traitSpecifiers.joined(separator: " ")
            switch verbosity.traitPosition {
            case .before:
                if let existingDescription = accessibilityDescription.nonEmpty() {
                    accessibilityDescription = "\(joinedTraits) \(existingDescription)"
                } else {
                    accessibilityDescription = joinedTraits
                }
            case .after, .none:
                if let existingDescription = accessibilityDescription.nonEmpty() {
                    let trailingPeriod = existingDescription.hasSuffix(".") ? "" : "."
                    accessibilityDescription = "\(existingDescription)\(trailingPeriod) \(joinedTraits)"
                } else {
                    accessibilityDescription = joinedTraits
                }
            }
        }

        if verbosity.includesContainerContext, let context = context {
            switch context {
            case let .series(index: index, count: count),
                 let .tabBarItem(index: index, count: count),
                 let .tab(index: index, count: count):
                accessibilityDescription = String(format:
                    strings.seriesContextFormat,
                    accessibilityDescription,
                    numberFormatter.string(from: .init(value: index))!,
                    numberFormatter.string(from: .init(value: count))!)

            case .listStart:
                let trailingPeriod = accessibilityDescription.hasSuffix(".") ? "" : "."
                accessibilityDescription = String(format: "%@%@ %@", accessibilityDescription, trailingPeriod, strings.listStartContext)

            case .listEnd:
                let trailingPeriod = accessibilityDescription.hasSuffix(".") ? "" : "."
                accessibilityDescription = String(format: "%@%@ %@", accessibilityDescription, trailingPeriod, strings.listEndContext)

            case .landmarkStart:
                let trailingPeriod = accessibilityDescription.hasSuffix(".") ? "" : "."
                accessibilityDescription = String(format: "%@%@ %@", accessibilityDescription, trailingPeriod, strings.landmarkStartContext)

            case .landmarkEnd:
                let trailingPeriod = accessibilityDescription.hasSuffix(".") ? "" : "."
                accessibilityDescription = String(format: "%@%@ %@", accessibilityDescription, trailingPeriod, strings.landmarkEndContext)

            case .dataTableCell:
                break
            }
        }

        if verbosity.includesHints {
            if traits.contains(.switchButton) && !traits.contains(.notEnabled) {
                if let existingHintDescription = hintDescription?.nonEmpty()?.strippingTrailingPeriod() {
                    hintDescription = String(format: strings.switchButtonTraitHintFormat, existingHintDescription)
                } else {
                    hintDescription = strings.switchButtonTraitHint
                }
            }

            if traits.contains(.textEntry) && !traits.contains(.notEnabled) {
                if traits.contains(.isEditing) {
                    hintDescription = strings.textEntryIsEditingTraitHint
                } else if traits.contains(.textArea) {
                    hintDescription = strings.textAreaTraitHint
                } else {
                    hintDescription = strings.textEntryTraitHint
                }
            }

            let hasHintOnly = (hint?.nonEmpty() != nil) && (label?.nonEmpty() == nil) && (value?.nonEmpty() == nil)
            let hidesAdjustableHint = traits.contains(.notEnabled) || traits.contains(.switchButton) || hasHintOnly
            if traits.contains(.adjustable), !hidesAdjustableHint {
                if let existingHintDescription = hintDescription?.nonEmpty()?.strippingTrailingPeriod() {
                    hintDescription = String(format: strings.adjustableTraitHintFormat, existingHintDescription)
                } else {
                    hintDescription = strings.adjustableTraitHint
                }
            }
        } else {
            hintDescription = nil
        }

        return (accessibilityDescription, hintDescription)
    }

    // MARK: - Private

    private var hidesAccessibilityValue: Bool {
        // A switch button's value ("1"/"0"/"2") is announced as an on/off/mixed trait, not as a value.
        traits.contains(.switchButton)
    }

    private func hidesAccessibilityLabel(backDescriptor: String) -> Bool {
        // To prevent duplication, Back Button elements omit their label if it matches the localized "Back" descriptor.
        guard traits.contains(.backButton), let label else { return false }
        return label.lowercased() == backDescriptor.lowercased()
    }
}

// MARK: -

private extension String {
    func nonEmpty() -> String? {
        isEmpty ? nil : self
    }

    func strippingTrailingPeriod() -> String {
        hasSuffix(".") ? String(dropLast()) : self
    }
}
