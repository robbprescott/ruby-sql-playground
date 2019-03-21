require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "activerecord"
  gem "pg"
  gem "byebug"
end

require "active_record"
require "minitest/autorun"

`dropdb playground; createdb playground`

ActiveRecord::Base.establish_connection(
  adapter: "postgresql",
  database: "playground",
  host: "localhost",
  username: "postgres")

class Slide < ActiveRecord::Base
  has_many :decks, -> { where(head_type: self.class.to_s) }, class_name: "Edge", foreign_key: "tail_id"

  connection.create_table table_name, :force => true do |t|
    t.string :name
  end
end

class Deck < ActiveRecord::Base
  has_many :children, -> { order(:sequence) }, class_name: "Edge", foreign_key: "head_id"
  has_many :parents, class_name: "Edge", foreign_key: "tail_id"

  def self.tree_sql_for(instance)
    tree_sql = <<-SQL
      WITH RECURSIVE search_tree(id, tail_id, tail_type, slide_ids) AS (
        SELECT id, tail_id, tail_type,
          CASE
            WHEN tail_type = 'Slide' THEN ARRAY[tail_id]
            ELSE ARRAY[]::integer[]
          END
        FROM edges
        WHERE head_id = #{instance.id}
          AND head_type = 'Deck'
        UNION ALL
        SELECT edges.id, edges.tail_id, edges.tail_type,
          CASE
            WHEN edges.tail_type = 'Slide' THEN slide_ids || edges.tail_id
            ELSE slide_ids
          END
        FROM search_tree
        JOIN edges ON edges.head_id = search_tree.tail_id
        WHERE search_tree.tail_type = 'Deck'
      )
      SELECT UNNEST(slide_ids) FROM search_tree
    SQL
  end

  def add_child(obj)
    Edge.create(head: self, tail: obj)
  end

  def slides
    subtree = self.class.tree_sql_for(self)
    Slide.where("id IN (#{subtree})")
  end

  connection.create_table table_name, :force => true do |t|
    t.string :name
  end
end

class Edge < ActiveRecord::Base
  belongs_to :tail, polymorphic: true
  belongs_to :head, polymorphic: true
  has_one :sequence

  connection.create_table table_name, :force => true do |t|
    t.string :tail_type
    t.integer :tail_id
    t.string :head_type
    t.integer :head_id
    t.integer :sequence
  end
end

describe "connecting a deck to it's slides" do
  before do
    [Slide, Deck, Edge].each { |ar| ar.delete_all }

    ActiveRecord::Base.logger = nil

    @slide1 = Slide.create(name: "slide 1")
    @slide2 = Slide.create(name: "slide 2")
    @slide3 = Slide.create(name: "slide 3")
    @slide4 = Slide.create(name: "slide 4")
    @slide5 = Slide.create(name: "slide 5")
    @slide6 = Slide.create(name: "slide 6")

    @deck1 = Deck.create(name: "deck 1")
    @deck2 = Deck.create(name: "deck 2")
    @deck3 = Deck.create(name: "deck 3")
    @deck4 = Deck.create(name: "deck 4")

    # ActiveRecord::Base.logger = Logger.new(STDOUT)
  end

  it "a deck can just have slides" do
    # Deck 1 = slide1 - slide6
    @deck1.add_child(@slide1)
    @deck1.add_child(@slide2)
    @deck1.add_child(@slide3)
    @deck1.add_child(@slide4)
    @deck1.add_child(@slide5)
    @deck1.add_child(@slide6)

    assert_equal 6, @deck1.children.count
    assert_equal 6, @deck1.slides.count
  end

  it "a deck can have decks and slides" do
    # Deck 1 = slide1 - slide2
    @deck1.add_child(@slide1)
    @deck1.add_child(@slide2)
    # Deck 2 = slide3 - slide4
    @deck2.add_child(@slide3)
    @deck2.add_child(@slide4)
    # Deck 3 = slide5 - slide6
    @deck3.add_child(@slide5)
    @deck3.add_child(@slide6)
    # Deck 4 = deck1 - deck3
    @deck4.add_child(@deck1)
    @deck4.add_child(@deck2)
    @deck4.add_child(@deck3)

    assert_equal 3, @deck4.children.count
    assert_equal 6, @deck4.slides.count
  end

  it "works with a bunch of super nested decks and slides" do
    @deck1.add_child(@deck2)
    @deck2.add_child(@deck3)
    @deck3.add_child(@deck4)
    @deck4.add_child(@slide1)
    @deck4.add_child(@slide2)

    assert_equal 2, @deck1.slides.count
    assert_equal 2, @deck2.slides.count
    assert_equal 2, @deck3.slides.count
    assert_equal 2, @deck4.slides.count
  end
end
