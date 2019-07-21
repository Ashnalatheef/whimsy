# get entry for @userid
entry = ASF::Person.find(@userid).members_txt(true)
raise Exception.new("unable to find member entry for #{userid}") unless entry

# identify file to be updated
members_txt = File.join(ASF::SVN['foundation'], 'members.txt')

# construct commit message
message = "Move #{ASF::Person.find(@userid).member_name} to #{@action}"

# update members.txt
_svn.update members_txt, message: message do |dir, text|
  # remove user's entry
  unless text.sub! entry, '' # e.g. if the workspace was out of date
    raise Exception.new("Failed to remove existing entry -- try refreshing")
  end

  # determine where to put the entry
  if @action == 'emeritus'
    index = text.index(/^\s\*\)\s/, text.index(/^Emeritus/))
    entry.sub! %r{\s*/\* deceased, .+?\*/},'' # drop the deceased comment if necessary
  elsif @action == 'active'
    index = text.index(/^\s\*\)\s/, text.index(/^Active/))
    entry.sub! %r{\s*/\* deceased, .+?\*/},'' # drop the deceased comment if necessary
  elsif @action == 'deceased'
    index = text.index(/^\s\*\)\s/, text.index(/^Deceased/))
    entry.sub! %r{\n}, " /* deceased, #{@dod} */\n" # add the deceased comment
  else
    raise Exception.new("invalid action #{action.inspect}")
  end

  # perform the insertion
  text.insert index, entry

  # save the updated text
  ASF::Member.text = text

  # return the updated (and normalized) text
  ASF::Member.text
end

# return updated committer info
_committer Committer.serialize(@userid, env)
