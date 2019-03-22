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
  belongs_to :deck

  connection.create_table table_name, :force => true do |t|
    t.string :name
    t.integer :deck_id
  end
end

class Deck < ActiveRecord::Base
  has_many :slides
  has_many :decks, class_name: "ObjToDeck", foreign_key: :obj_id

  def self.find_all_children_decks_sql(instance)
    <<-SQL
      WITH RECURSIVE search_tree(child_id, deck_ids) AS (
        SELECT obj_to_decks.deck_id, ARRAY[decks.id]
        FROM decks
        LEFT JOIN obj_to_decks ON obj_to_decks.obj_id = decks.id AND obj_type = 'Deck'
        WHERE decks.id = #{instance.id}
        UNION ALL
        SELECT obj_to_decks.deck_id, deck_ids || decks.id
        FROM search_tree
        JOIN decks ON decks.id = search_tree.child_id
        LEFT JOIN obj_to_decks ON obj_to_decks.obj_id = decks.id AND obj_to_decks.obj_type = 'Deck'
      )
      SELECT UNNEST(deck_ids) FROM search_tree
    SQL
  end


  def add_child(obj)
    if obj.is_a?(Slide)
      obj.update(deck: self)
    else
      ObjToDeck.create(obj: self, deck: obj)
    end
  end

  def all_slides
    subtree = self.class.find_all_children_decks_sql(self)
    Slide.where("deck_id IN (#{subtree})")
  end

  connection.create_table table_name, :force => true do |t|
    t.string :name
  end
end

class ObjToDeck < ActiveRecord::Base
  belongs_to :deck
  belongs_to :obj, polymorphic: true

  connection.create_table table_name, :force => true do |t|
    t.string :obj_type
    t.integer :obj_id
    t.integer :deck_id
  end
end

describe "connecting a deck to it's slides" do
  before do
    [Slide, Deck, ObjToDeck].each { |ar| ar.delete_all }

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

    # assert_equal 6, @deck1.children.count
    assert_equal 6, @deck1.all_slides.count
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

    # assert_equal 3, @deck4.children.count
    assert_equal 6, @deck4.all_slides.count
  end

  it "works with a bunch of super nested decks and slides" do
    @deck1.add_child(@deck2)
    @deck2.add_child(@deck3)
    @deck3.add_child(@deck4)
    @deck4.add_child(@slide1)
    @deck4.add_child(@slide2)

    assert_equal 2, @deck1.all_slides.count
    assert_equal 2, @deck2.all_slides.count
    assert_equal 2, @deck3.all_slides.count
    assert_equal 2, @deck4.all_slides.count
  end
end
