# frozen_string_literal: true

require "test_helper"

class PhotoTagSetTest < Minitest::Test
  def setup
    @tag_set = AiLens::PhotoTagSet.new(
      photo_index: 0,
      tags: [
        { facet: "showcase", score: 0.9 },
        { facet: "detail", score: 0.7 },
        { facet: "identifier", score: 0.4 }
      ],
      open_tags: [
        { facet: "artistic", score: 0.6 },
        { facet: "vintage_feel", score: 0.3 }
      ]
    )
  end

  def test_photo_index
    assert_equal 0, @tag_set.photo_index
  end

  def test_tags_sorted_by_score_descending
    scores = @tag_set.tags.map { |t| t[:score] }
    assert_equal [0.9, 0.7, 0.4], scores
  end

  def test_open_tags_sorted_by_score_descending
    scores = @tag_set.open_tags.map { |t| t[:score] }
    assert_equal [0.6, 0.3], scores
  end

  def test_tagged_returns_true_for_existing_facet
    assert @tag_set.tagged?(:showcase)
    assert @tag_set.tagged?("detail")
  end

  def test_tagged_returns_false_for_missing_facet
    refute @tag_set.tagged?(:damage)
    refute @tag_set.tagged?("documentation")
  end

  def test_score_returns_score_for_existing_facet
    assert_in_delta 0.9, @tag_set.score(:showcase)
    assert_in_delta 0.7, @tag_set.score("detail")
  end

  def test_score_returns_zero_for_missing_facet
    assert_in_delta 0.0, @tag_set.score(:damage)
  end

  def test_primary_facet
    assert_equal :showcase, @tag_set.primary_facet
  end

  def test_primary_facet_nil_when_empty
    empty = AiLens::PhotoTagSet.new(photo_index: 0, tags: [])
    assert_nil empty.primary_facet
  end

  def test_facets
    assert_equal [:showcase, :detail, :identifier], @tag_set.facets
  end

  def test_all_tags_combines_tags_and_open_tags
    all = @tag_set.all_tags
    assert_equal 5, all.size
    facet_names = all.map { |t| t[:facet] }
    assert_includes facet_names, "showcase"
    assert_includes facet_names, "artistic"
  end

  def test_normalizes_string_keys
    tag_set = AiLens::PhotoTagSet.new(
      photo_index: 1,
      tags: [{ "facet" => "showcase", "score" => 0.8 }],
      open_tags: [{ "facet" => "custom", "score" => 0.5 }]
    )

    assert tag_set.tagged?(:showcase)
    assert_in_delta 0.8, tag_set.score(:showcase)
    assert_equal 2, tag_set.all_tags.size
  end

  def test_empty_open_tags_default
    tag_set = AiLens::PhotoTagSet.new(
      photo_index: 0,
      tags: [{ facet: "showcase", score: 0.9 }]
    )

    assert_equal [], tag_set.open_tags
    assert_equal 1, tag_set.all_tags.size
  end
end
