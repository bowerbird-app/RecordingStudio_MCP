# frozen_string_literal: true

module RecordingStudioMcp
  module Registry
    module Skills
      def register_skill(name:, **)
        registration = skill_registration(name, **)
        configuration.add_skill(registration)
        configuration.update_skill_catalog { |catalog| catalog.add(skills_entry(registration)) }
        registration
      end

      def exposed_skills(access_grant:)
        policy = configuration.skill_policy
        skills_for_grant(access_grant).select { |registration| expose_skill?(registration, policy, access_grant) }
      end

      private

      def skills_for_grant(access_grant)
        server = configuration.catalogs.server_for(api: Catalog.api_from(access_grant))
        return [] if server.nil?

        server.skills.values.map { |skill| skills_entry(skill) }
      end

      def skill_registration(name, **options)
        parsed_name = RecordingStudioMcp::Skills::SkillName.parse(name)
        raise ArgumentError, "invalid skill name" if parsed_name.nil?
        raise ArgumentError, "available_if must be callable" unless skill_hook?(options[:available_if])

        Registrations::Skill.new(name: parsed_name, **skill_attrs(options))
      end

      def skill_attrs(options)
        skill_copy(options).merge(
          body: options[:body],
          tools: Array(options[:tools]).map(&:to_s),
          path: options[:path].present? ? absolute_skill_path(options[:path]) : nil,
          available_if: options[:available_if]
        )
      end

      def skill_copy(options)
        {
          type: options[:type]&.to_s,
          title: options[:title].to_s.presence,
          description: options[:description].to_s.presence
        }
      end

      def skills_entry(registration)
        RecordingStudioMcp::Skills::Registration.new(
          name: registration.name,
          path: registration.path,
          available_if: registration.available_if,
          type: registration.type,
          title: registration.title,
          description: registration.description,
          body: registration.body,
          tools: registration.tools
        )
      end

      def skill_hook?(available_if)
        available_if.nil? || available_if.respond_to?(:call)
      end

      def absolute_skill_path(path)
        Pathname.new(File.expand_path(path.to_s))
      end

      def expose_skill?(registration, policy, access_grant)
        skill_available?(registration, access_grant) && skill_allowed?(policy, registration, access_grant)
      end

      def skill_available?(registration, access_grant)
        hook = registration.available_if
        hook.nil? || hook.call(access_grant: access_grant) == true
      end

      def skill_allowed?(policy, registration, access_grant)
        return true if policy.nil?
        return false unless policy.respond_to?(:call)

        policy.call(skill: registration, access_grant: access_grant) == true
      end
    end
  end
end
