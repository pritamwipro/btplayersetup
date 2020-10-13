# frozen_string_literal: true

module Bundle
  module Checker
    class Base
      # Implement these in any subclass
      # PACKAGE_TYPE = :pkg
      # PACKAGE_TYPE_NAME = "Package"

      def exit_early_check(packages, no_upgrade:)
        work_to_be_done = packages.find do |pkg|
          !installed_and_up_to_date?(pkg, no_upgrade: no_upgrade)
        end

        Array(work_to_be_done)
      end

      def failure_reason(name, no_upgrade:)
        reason = if no_upgrade
          "needs to be installed."
        else
          "needs to be installed or updated."
        end
        "#{self.class::PACKAGE_TYPE_NAME} #{name} #{reason}"
      end

      def full_check(packages, no_upgrade:)
        packages.reject { |pkg| installed_and_up_to_date?(pkg, no_upgrade: no_upgrade) }
                .map { |pkg| failure_reason(pkg, no_upgrade: no_upgrade) }
      end

      def checkable_entries(all_entries)
        all_entries.select { |e| e.type == self.class::PACKAGE_TYPE }
                   .reject(&Bundle::Skipper.method(:skip?))
      end

      def format_checkable(entries)
        checkable_entries(entries).map(&:name)
      end

      def installed_and_up_to_date?(_pkg, no_upgrade: false)
        raise NotImplementedError
      end

      def find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
        requested = format_checkable entries

        if exit_on_first_error
          exit_early_check(requested, no_upgrade: no_upgrade)
        else
          full_check(requested, no_upgrade: no_upgrade)
        end
      end
    end

    module_function

    CheckResult = Struct.new :work_to_be_done, :errors

    CHECKS = {
      taps_to_tap:         "Taps",
      casks_to_install:    "Casks",
      apps_to_install:     "Apps",
      formulae_to_install: "Formulae",
      formulae_to_start:   "Services",
    }.freeze

    def check(global: false, file: nil, exit_on_first_error: false, no_upgrade: false, verbose: false)
      @dsl ||= Bundle::Dsl.new(Brewfile.read(global: global, file: file))

      check_method_names = CHECKS.keys

      errors = []
      enumerator = exit_on_first_error ? :find : :map

      work_to_be_done = check_method_names.public_send(enumerator) do |check_method|
        check_errors =
          send(check_method, exit_on_first_error: exit_on_first_error, no_upgrade: no_upgrade, verbose: verbose)
        any_errors = check_errors.any?
        errors.concat(check_errors) if any_errors
        any_errors
      end

      work_to_be_done = Array(work_to_be_done).flatten.any?

      CheckResult.new work_to_be_done, errors
    end

    def casks_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
      Bundle::Checker::CaskChecker.new.find_actionable(
        @dsl.entries,
        exit_on_first_error: exit_on_first_error, no_upgrade: no_upgrade, verbose: verbose,
      )
    end

    def formulae_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
      Bundle::Checker::BrewChecker.new.find_actionable(
        @dsl.entries,
        exit_on_first_error: exit_on_first_error, no_upgrade: no_upgrade, verbose: verbose,
      )
    end

    def taps_to_tap(exit_on_first_error: false, no_upgrade: false, verbose: false)
      Bundle::Checker::TapChecker.new.find_actionable(
        @dsl.entries,
        exit_on_first_error: exit_on_first_error, no_upgrade: no_upgrade, verbose: verbose,
      )
    end

    def apps_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
      Bundle::Checker::MacAppStoreChecker.new.find_actionable(
        @dsl.entries,
        exit_on_first_error: exit_on_first_error, no_upgrade: no_upgrade, verbose: verbose,
      )
    end

    def formulae_to_start(exit_on_first_error: false, no_upgrade: false, verbose: false)
      Bundle::Checker::BrewServiceChecker.new.find_actionable(
        @dsl.entries,
        exit_on_first_error: exit_on_first_error, no_upgrade: no_upgrade, verbose: verbose,
      )
    end

    def reset!
      @dsl = nil
      Bundle::CaskDumper.reset!
      Bundle::BrewDumper.reset!
      Bundle::MacAppStoreDumper.reset!
      Bundle::TapDumper.reset!
      Bundle::BrewServices.reset!
    end
  end
end
