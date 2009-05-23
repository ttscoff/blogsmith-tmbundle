require File.dirname(__FILE__) + '/stemmable'
# Add stemmable to class string
class String
  include Stemmable
  # Can't use respond to 'cos it will only detect the class level functions
  # There must be a cleaner way of doing this but pickaxe found wanting again
  # maybe "".respond_to? :singularize - but I don't like it - too clever
  if String.public_instance_methods.detect{ |x| x == "singularize" }.nil?
    # This is a quick hack so it will test outside of Rails
    # If you want it to work properly get the Rails string extensions
    def singularize
      if self =~ /ies$/
        self.sub( /ies$/, 'y')   
      elsif self =~ /is$/
        self
      else
        self.sub( /s$/, '')
      end
      
    end
  end
end

# = Keyword Density
# Has methods to get the keyword
# density from a string - stop list adapted from from http://tools.seobook.com/general/keyword-density/source.php
# 
# == Example use
#
# First, create a class instance
#      density = KeywordDensity.new
#
# Now do the density calculations
#
#      density.get_keyword_density("Hello Hello instant teapots that jumps")
#
# Each word is made lower case and singular, all punctuation is removed.
# 
# if you haven't removed HTML markup it will be counted
#
# text.gsub(/<[^>]*>/) 
#
# will usually get rid of it, as long as the text isn't full of words bracketed
# with <>, in which case you're on your own.
#
# The words_count instance variable will have phrases of the form [["hello"],2],
# as in a single-word phrase (hello) that occurs twice, multi word phrases
# would look like [["hello","instant","teapot"],1]. This gives you the phrase
# and the number of occurrences - you can do something like this:
#
#      density.words_count.each do |phrase,count|
#        phrase = phrase.join ' '
#        num_words = phrase.length
#        # Do something with them ...
#      end
#
# There are also stemmed versions of this, held in different instance variables.
# Stemmed means that, for example, insurance and insure both become insur. There
# is a stemmable module added into String (see the module for its origins).
#
# This is used currently to generate keyword lists for HTML meta tags from
# raw content. 
#
# == Search words 
#
# You can give the class a list of words or phrases on instantiation or set it using =
# It will then give you the frequency in the set it has both
# for stemmed and non. Carrying on the previous example:
#
#     density.search_words =["hello hello", "teapot", "fred"]
#
#     puts density.search_word_counts
#
#     > { "hello hello" => 1, "teapot" => 1, "fred" => 0 }
# 
# As before there is a stemmed version, stemmed_search_word_counts.
#
# == Class methods 
#
# Generally used to help put things into database fields for reference
#
# The class-level methods should be easy to follow from their names
# Also, for testing purposes, there is a hack to String that is applied
# outside of Rails to get the singularize method.
#
# For more examples and so on look in the RSpec tests
#
class KeywordDensity
  # the stop word list
  attr_reader :stop_words
  # The list of search words or phrases we are interested in
  attr_reader :stemmed_search_word_counts
  # The list of search words or phrases we are interested in
  attr_reader :search_word_counts
  # Hashes stemmed keywords and their count
  # e.g. {["bert","fred"] => 6, ["jim"] => 1]}
  attr_reader :stemmed_words_count
  # words we counted in order 
  attr_reader :stemmed_words
  # Total number of stemmed words (after stop list has been applied)
  attr_reader :num_stemmed_words
  # Array of hashes of arrays of keywords and their count
  # e.g. ["bert","fred"] => 6
  attr_reader :words_count
  # words we counted in order 
  attr_reader :words
  # Total number of words (after stop list has been applied)
  attr_reader :num_words
  # Current set of search words or phrases
  attr_accessor :current_search_words
  # Current string we've just processed
  attr_reader :current_string
  
  class << self
    # Class method to create a stem from the passed word or phrase
    # use in database methods etc.
    def make_stem(word_phrase)
      word_phrase.split( /[ ]+/).collect { |w| w.downcase.stem}.join ' '
    end

    def make_phrase_singular(word_phrase)
      word_phrase.downcase.gsub(/crisis/,'crises').split( /[ ]+/).collect { |w| w.singularize }.join ' '
    end

    # remove everything that isn't alpha and force the string to be lower case
    def remove_noise(text)
      text.gsub(/'s/,' ').gsub(/[^[:alpha:]]/,' ').gsub(/ [ ]*/, ' ').downcase.strip
    end
  
  end
  # Take an array of strings and reinitialise the searches
  def current_search_words=(search_word_list)
    @current_stemmed_search_words = search_word_list
    @stemmed_search_word_counts = {}
    search_word_list.each { |w|  @stemmed_search_word_counts[KeywordDensity.make_stem(w)] = 0}
    calculate_stemmed_search_word_counts
    @current_search_words = search_word_list
    @search_word_counts = {}
    search_word_list.each { |w|  @search_word_counts[KeywordDensity.make_phrase_singular(w)] = 0}
    calculate_search_word_counts
  end

  # perform calculations and put them in the instance variables
  def get_keyword_density(text)
    @current_string = text
    @stemmed_words_count, @stemmed_words = perform_calculation( text, false )
    @num_stemmed_words = @stemmed_words.length
    @words_count, @words = perform_calculation( text, false )
    @num_words = @words.length
    calculate_stemmed_search_word_counts
    calculate_search_word_counts
    nil
  end
  
  # is the given word a stop word
  def stop_word?(word)
    # Bad implementation - should really use binary search
    @stop_words.include?(word)
  end
  
  # remove all words less than 2 characters or in the stop list
  def clean_words_string(words,use_stem = true)
    if use_stem
      block = lambda { |word| KeywordDensity.make_stem(word) }
    else
      block = lambda { |word| KeywordDensity.make_phrase_singular(word) }
    end
    words.split(' ').delete_if do |word|
      word.length <= 2 ||
        stop_word?(word)
    end.collect( &block )
  end
  
  # key list is a list of keywords to search for, stop words file is the name
  # of a file to use instead of the default list
  def initialize(search_word_list = [],stop_words_file = nil)
    set_stop_words(stop_words_file)
    @current_search_words = search_word_list
    calculate_stemmed_search_word_counts
    calculate_search_word_counts
    @current_string = ""
  end
    
  private
    
  # This will set the stop words. If an optional file name is given it will
  # get them from there
  def set_stop_words(file_name=nil)
    unless file_name
      @stop_words ||= DEFAULT_STOP_WORDS
    else
      @stop_words = IO.read(file_name).collect { |l| l.chomp! }.delete_if{ |w| w.length <= 2 || w =~ /[^[:alpha:]]/}
    end
  end

  # Group phrases by the number of words passed in
  def group_by_n( word_list, n)
    n_list = {}
    word_list.each_index do |ind|
      break if word_list[ind+n].nil?
      word_group = word_list[(ind..ind+n)]
      n_list[word_group] ||= 0
      n_list[word_group] += 1
    end
    n_list
  end
  
  # Scan the words list for each and aggregate scores 
  # returns a hash of phrases in arrays and their counts
  def perform_calculation( words, use_stem = true )
    word_list = clean_words_string(KeywordDensity::remove_noise(words),use_stem)
    words_count = {}
    (0..2).each { |n| words_count.merge! group_by_n(word_list,n) }
    [words_count, word_list]
  end
  
  def calculate_stemmed_search_word_counts
    @stemmed_search_word_counts = {}
    # now we need a list of words of the form ['aa','bb']
    # so we can see if they are in our stemmed word counts
    @current_search_words.each do  |k| 
      search_words = clean_words_string(k)
      @stemmed_search_word_counts[k] = @stemmed_words_count[search_words] rescue 0
    end
  end

  def calculate_search_word_counts
    @search_word_counts = {}
    # now we need a list of words of the form ['aa','bb']
    # so we can see if they are in our stemmed word counts
    @current_search_words.each do  |k| 
      search_words = clean_words_string(k,false)
      @search_word_counts[k] = @words_count[search_words] rescue 0
    end
  end

  DEFAULT_STOP_WORDS = %w{
about
above
according
across
actually
adj
after
afterwards
again
against
all
almost
alone
along
already
also
although
always
among
amongst
and
another
any
anyhow
anyone
anything
anywhere
are
aren
arent
around
arpa
became
because
become
becomes
becoming
been
before
beforehand
begin
beginning
behind
being
below
beside
besides
between
beyond
billion
both
but
buy
can
cannot
cant
caption
click
com
copy
could
couldn
couldnt
did
didn
didnt
does
doesn
doesnt
don
dont
down
during
each
edu
eight
eighty
either
else
elsewhere
end
ending
enough
etc
even
ever
every
everyone
everything
everywhere
except
few
fifty
find
first
five
for
former
formerly
forty
found
four
free
from
further
get
gmt
gov
had
has
hasn
hasnt
have
haven
havent
hed
hell
help
hence
her
here
hereafter
hereby
herein
heres
hereupon
hers
herself
hes
him
himself
his
home
homepage
how
however
htm
html
http
hundred
ill
inc
inc
inc
indeed
information
instead
int
into
isn
isnt
its
its
itself
ive
join
last
later
latter
least
length
less
let
lets
like
likely
ltd
made
make
makes
many
maybe
meantime
meanwhile
microsoft
might
mil
million
miss
more
moreover
most
mostly
mrs
msie
much
must
myself
namely
neither
net
netscape
never
nevertheless
new
next
nine
ninety
nobody
none
nonetheless
noone
nor
not
nothing
now
nowhere
null
off
often
once
one
ones
only
onto
org
org
other
others
otherwise
our
ours
ourselves
out
over
overall
own
page
per
perhaps
rather
recent
recently
reserved
ring
same
seem
seemed
seeming
seems
seven
seventy
several
she
shed
shell
shes
should
shouldn
shouldnt
since
site
six
sixty
some
somehow
someone
something
sometime
sometimes
somewhere
still
stop
such
taking
ten
test
text
than
that
thatll
thats
the
their
them
themselves
then
thence
there
thereafter
thereby
therefore
therein
therell
theres
thereupon
these
they
theyd
theyll
theyre
theyve
thirty
this
those
though
thousand
three
through
throughout
thru
thus
together
too
toward
towards
trillion
twenty
two
under
unless
unlike
unlikely
until
upon
use
used
using
very
via
was
wasn
wasnt
web
webpage
website
wed
welcome
well
well
were
were
weren
werent
weve
what
whatever
whatll
whats
when
whence
whenever
where
whereafter
whereas
whereby
wherein
whereupon
wherever
whether
which
while
whither
who
whod
whoever
whole
wholl
whom
whomever
whos
whose
why
width
will
with
within
without
won
wont
would
wouldn
wouldnt
www
yes
yet
you
youd
youll
your
youre
yours
yourself
yourselves
youve
  }
end
