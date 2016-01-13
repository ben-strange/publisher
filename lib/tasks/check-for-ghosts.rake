require 'local_authority_data_importer'
require 'local_interaction_importer'
require 'local_authority_interaction_ghost_detector'

namespace :check_for_ghosts do
  def detector
    @_detector ||= LocalAuthorityInteractionGhostDetector.new(LocalInteractionImporter.fetch_data())
  end

  def with_output_file(name)
    output_filename = Rails.root.join("#{name}_#{Time.zone.today.iso8601}.csv")
    CSV.open(output_filename, 'w') do |output|
      output.puts ['LA Name', 'LA SNAC', 'LGSL', 'LGIL', 'URL', 'status']
      yield output
    end
    output_filename
  end

  def iterate_over_interactions(on_new_authority: nil, &interaction_block)
    current_la = nil
    detector.detect_ghosts do |la, lai, ghost_status|
      if current_la != la
        on_new_authority.call(current_la, la) unless on_new_authority.nil?
        current_la = la
      end
      interaction_block.call(la, lai, ghost_status)
    end
    on_new_authority.call(current_la, nil) unless on_new_authority.nil?
  end

  desc "Compare local authority interactions in our DB against the local.directgov CSV export to detect \"ghosts\"."
  task :run => :environment do
    total_count = ghosts_count = current_ghost_count = 0
    output_filename = with_output_file 'ghosts_in_local_authority_interactions' do |output|
      iterate_over_interactions(
        on_new_authority: ->(current_la, new_la) do
          puts " - #{current_ghost_count} ghosts" if current_la.present?
          print "#{new_la.name} (#{new_la.snac}): #{new_la.local_interactions.count} interactions" if new_la.present?
          current_ghost_count = 0
        end
      ) do |la, lai, ghost_status|
        total_count += 1
        if ghost_status != :interaction_in_input
          output.puts [la.name, la.snac, lai.lgsl_code, lai.lgil_code, lai.url, ghost_status]
          ghosts_count += 1
          current_ghost_count += 1
        end
      end
    end
    puts "Total Interactions: #{total_count}, Total Ghosts: #{ghosts_count}, Data: #{output_filename}"
  end

  desc "Remove any local authority interactions that appear in our DB but not in the local.directgov CSV export."
  task :remove, [] => :environment do |_task, args|
    interaction_limit =
      if ENV['INTERACTION_LIMIT']
        Integer(ENV['INTERACTION_LIMIT'])
      else
        100_000
      end
    possible_statuses = [:interaction_in_input_to_be_deleted, :interaction_not_in_input, :authority_not_in_input]
    statuses_to_remove =
      if args.extras.any?
        args.extras.map { |x| x.to_sym }.select { |x| possible_statuses.include? x }
      else
        [:interaction_not_in_input]
      end
    if statuses_to_remove.empty?
      puts "Usage: `rake check_for_ghosts:remove` or `rake check_for_ghosts:remove[statuses_to_remove]`"
      puts "  If statuses_to_remove is omitted only interaction_not_in_input ghosts will be removed."
      puts "  If statuses_to_remove is provided statuses not in #{possible_statuses.inspect} will be ignored."
      abort "There are no statuses to remove. Check that the arguments passed to this task are appropriate."
    else
      if detector.directgov_interactions_count < interaction_limit
        exit_text = "WARNING! Less than #{interaction_limit} interactions in directgov data (found #{detector.directgov_interactions_count}) - halting run!\n"
        exit_text += "Specify a different limit via environment variable INTERACTION_LIMIT if you want to run anyway."
        abort exit_text
      else
        puts "More than #{interaction_limit} interactions in directgov data (found #{detector.directgov_interactions_count}) - proceeeding."
        puts "Removing ghost interactions with statuses: #{statuses_to_remove.inspect}"
        total_count = removed_count = ghosts_count = 0
        output_filename = with_output_file 'removed_ghosts_in_local_authority_interactions' do |output|
          to_keep = []
          to_remove = []
          iterate_over_interactions(
            on_new_authority: ->(current_la, new_la) do
              if current_la.present?
                current_la.local_interactions.substitute(to_keep)
                to_remove.each do |(lai, ghost_status)|
                  output.puts [current_la.name, current_la.snac, lai.lgsl_code, lai.lgil_code, lai.url, ghost_status]
                end
              end
              to_keep = []
              to_remove = []
            end
          ) do |la, lai, ghost_status|
            total_count += 1
            ghosts_count +=1 if ghost_status != :interaction_in_input
            if statuses_to_remove.include? ghost_status
              to_remove << [lai, ghost_status]
              removed_count += 1
            else
              to_keep << lai
            end
            print "\rT: #{total_count} / G: #{ghosts_count} / R: #{removed_count}"
          end
        end
        puts "\rTotal Interactions: #{total_count}, Total Ghosts: #{ghosts_count}, Total Removed: #{removed_count}, Data: #{output_filename}"
      end
    end
  end
end