# Public member data
#
# Output looks like:
#
# {
#  "last_updated": "2015-11-29 23:45:50 UTC", // date of members.txt
#  "code_version": "2016-02-02 17:20:38 UTC",
#  "members": [
#    "m1",
#    "m2",
#    ...
# ],
#  "ex_members": {
#    "e1": "Emeritus (Non-voting) Member",
#    "e2": "Deceased Member",
#    ...
#   }
# }
#
#
#

require_relative 'public_json_common'

CODEVERSION = ASF.library_mtime rescue nil

# gather member info

info = {
    last_updated: (ASF::Member.svn_change rescue nil),
    code_version: CODEVERSION
}

info[:members] = Array.new
info[:ex_members] = Hash.new

ASF::Member.list.each do |e,v|
  s = v['status']
  if s == nil
    info[:members] << e
  else
    info[:ex_members][e] = s
  end
end

# output results (the JSON module does not support sorting, so we pre-sort and rely on insertion order preservation)
info[:members].sort!
info[:ex_members] = Hash[info[:ex_members].sort]

public_json_output(info)

if changed? and @old_file
  # for validating UIDs
  uids = ASF::Person.list().map(&:id)
  info[:members].each do |id|
    Wunderbar.warn "member: unknown uid '#{id}'" unless uids.include?(id)
  end
end
