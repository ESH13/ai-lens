# frozen_string_literal: true

module AiLens
  class PhotoTagSet
    attr_reader :photo_index, :tags, :open_tags

    def initialize(photo_index:, tags:, open_tags: [])
      @photo_index = photo_index
      @tags = normalize_tags(tags).sort_by { |t| -t[:score] }
      @open_tags = normalize_tags(open_tags).sort_by { |t| -t[:score] }
    end

    def tagged?(facet)
      tags.any? { |t| t[:facet].to_sym == facet.to_sym }
    end

    def score(facet)
      tag = tags.find { |t| t[:facet].to_sym == facet.to_sym }
      tag ? tag[:score] : 0.0
    end

    def primary_facet
      tags.first&.dig(:facet)&.to_sym
    end

    def facets
      tags.map { |t| t[:facet].to_sym }
    end

    def all_tags
      tags + open_tags
    end

    private

    def normalize_tags(tag_array)
      Array(tag_array).map do |t|
        { facet: (t[:facet] || t["facet"]).to_s, score: (t[:score] || t["score"]).to_f }
      end
    end
  end
end
