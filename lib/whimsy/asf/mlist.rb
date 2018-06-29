module ASF

  module MLIST
    # utility methods for handling mailing list subscriptions and moderations

    # whilst the source files are not particularly difficult to parse, it makes
    # sense to centralise access so any necessary changes can be localised

    # Note that email matching is case blind, but the original case is returned
    # list and domain names are always returned as lower-case

    # Potentially also the methods could check if access was allowed.
    # This is currently done by the callers
    
    # Return an array of board subscribers followed by the file update time
    def self.board_subscribers
      return list_filter('sub', 'apache.org', 'board'), (File.mtime(LIST_TIME) rescue File.mtime(LIST_SUBS))
    end

    # Return an array of members@ subscribers followed by the file update time
    def self.members_subscribers
      return list_filter('sub', 'apache.org', 'members'), (File.mtime(LIST_TIME) rescue File.mtime(LIST_SUBS))
    end

    # Return an array of private@pmc subscribers followed by the file update time
    # By default does not return the standard archivers
    def self.private_subscribers(pmc, archivers=false)
      return list_filter('sub', "#{pmc}.apache.org", 'private', archivers), (File.mtime(LIST_TIME) rescue File.mtime(LIST_SUBS))
    end

    # return a hash of subscriptions for the list of emails provided
    # the following keys are added to the response hash:
    # :subtime - the timestamp when the data was last updated
    # :subscriptions - an array of pairs: [list name, subscriber email]
    # N.B. not the same format as the moderates() method
    def self.subscriptions(emails, response = {})
      
      return response unless File.exists? LIST_SUBS

      response[:subscriptions] = []
      response[:subtime] = (File.mtime(LIST_TIME) rescue File.mtime(LIST_SUBS))

      list_parse('sub') do |dom, list, subs|
        emails.each do |email|
          if downcase(subs).include? email.downcase
            response[:subscriptions] << ["#{list}@#{dom}", email]
          end
        end
      end
      response
    end

    # return a hash of digest subscriptions for the list of emails provided
    # the following keys are added to the response hash:
    # :digtime - the timestamp when the data was last updated
    # :digests - an array of pairs: [list name, subscriber email]
    # N.B. not the same format as the moderates() method
    def self.digests(emails, response = {})
      
      return response unless File.exists? LIST_DIGS

      response[:digests] = []
      response[:digtime] = (File.mtime(LIST_TIME) rescue File.mtime(LIST_DIGS))

      list_parse('dig') do |dom, list, subs|
        emails.each do |email|
          if downcase(subs).include? email.downcase
            response[:digests] << ["#{list}@#{dom}", email]
          end
        end
      end
      response
    end

    # return the mailing lists which are moderated by any of the list of emails
    # the following keys are added to the response hash:
    # :modtime - the timestamp when the data was last updated
    # :moderates - a hash. key: list name; entry: array of moderators
    # N.B. not the same format as the subscriptions() method
    def self.moderates(user_emails, response = {})

      return response unless File.exists? LIST_MODS

      response[:moderates] = {}
      response[:modtime] = (File.mtime(LIST_TIME) rescue File.mtime(LIST_MODS))
      user_emails.map!{|m| m.downcase} # outside loop
      list_parse('mod') do |dom, list, emails|
        matching = emails.select{|m| user_emails.include? m.downcase}
        response[:moderates]["#{list}@#{dom}"] = matching unless matching.empty?
      end
      response
    end

    # for a mail domain, extract related lists and their moderators
    # also returns the time when the data was last checked
    # If podling==true, then also check for old-style podling names
    def self.list_moderators(mail_domain, podling=false)

      return nil, nil unless File.exist? LIST_MODS

      moderators = {}
      list_parse('mod') do |dom, list, subs|

        # drop infra test lists
        next if list =~ /^infra-[a-z]$/
        next if dom == 'incubator.apache.org' && list =~ /^infra-dev2?$/

        # normal tlp style:
        #/home/apmail/lists/commons.apache.org/dev/mod
        # possible podling styles (new, old):
        #/home/apmail/lists/batchee.apache.org/dev/mod
        #/home/apmail/lists/incubator.apache.org/blur-dev/mod
        next unless "#{mail_domain}.apache.org" == dom or
           (podling && dom == 'incubator.apache.org' && list =~ /^#{mail_domain}-/)
        moderators["#{list}@#{dom}"] = subs.sort
      end
      return moderators.to_h, (File.mtime(LIST_TIME) rescue File.mtime(LIST_MODS))
    end

    # for a mail domain, extract related lists and their subscribers (default only the count)
    # also returns the time when the data was last checked
    # If podling==true, then also check for old-style podling names
    def self.list_subscribers(mail_domain, podling=false, list_subs=false)

      return nil, nil unless File.exist? LIST_SUBS

      subscribers = {}
      list_parse('sub') do |dom, list, subs|

        # drop infra test lists
        next if list =~ /^infra-[a-z]$/
        next if dom == 'incubator.apache.org' && list =~ /^infra-dev2?$/

        # normal tlp style:
        #/home/apmail/lists/commons.apache.org/dev/mod
        # possible podling styles (new, old):
        #/home/apmail/lists/batchee.apache.org/dev/mod
        #/home/apmail/lists/incubator.apache.org/blur-dev/mod
        next unless "#{mail_domain}.apache.org" == dom or
           (podling && dom == 'incubator.apache.org' && list =~ /^#{mail_domain}-/)
        subscribers["#{list}@#{dom}"] = list_subs ? subs.sort : subs.size
      end
      return subscribers.to_h, (File.mtime(LIST_TIME) rescue File.mtime(LIST_SUBS))
    end

    private

    def self.downcase(array)
      array.map{|m| m.downcase}
    end

    def self.isRecent(file)
      return File.exist?(file) && ( Time.now - File.mtime(file) ) < 60*60*5
    end

    # Filter the appropriate list, matching on domain and list
    # Params:
    # - type: 'mod' or 'sub' or 'dig'
    # - matchdom: must match the domain (e.g. 'httpd.apache.org')
    # - matchlist: must match the list (e.g. 'dev')
    # - archivers: whether to include standard ASF archivers (default true)
    # The email addresses are returned as an array. May be empty.
    # If there is no match, then nil is returned
    def self.list_filter(type, matchdom, matchlist, archivers=true)
      list_parse(type) do |dom, list, emails|
          if matchdom == dom && matchlist == list
            if archivers
              return emails
            else
              return (emails - ARCHIVERS) - ["#{list}-archive@#{dom}"]
            end
          end
      end
      return nil
    end
    
    # Parses the list-mods/list-subs files
    # Param: type = 'mod' or 'sub' or 'dig'
    # Yields:
    # - domain (e.g. [xxx.].apache.org)
    # - list (e.g. dev)
    # - emails as an array
    def self.list_parse(type)
      if type == 'mod'
        path = LIST_MODS
        suffix = '/mod'
      elsif type == 'sub'
        path = LIST_SUBS
        suffix = ''
      elsif type == 'dig'
        path = LIST_DIGS
        suffix = ''
      else
        raise ArgumentError.new('type: expecting mod or sub')
      end
      # split file into paragraphs
      File.read(path).split(/\n\n/).each do |stanza|
        # domain may start in column 1 or following a '/'
        # match [/home/apmail/lists/][accumulo.]apache.org/dev[/mod]
        # list names can include '-': empire-db
        # or    [/home/apmail/lists/]apachecon.com/announce[/mod]
        match = stanza.match(%r{(?:^|/)([-\w]*\.?apache\.org|apachecon\.com)/(.*?)#{suffix}(?:\n|\Z)})
        if match
          dom = match[1].downcase # just in case
          list = match[2].downcase # just in case
          # Keep original case of email addresses
          yield dom, list, stanza.scan(/^(.*@.*)/).flatten
        else
          # don't allow mismatches as that means the RE is wrong
          line=stanza[0..(stanza.index("\n")|| -1)]
          raise ArgumentError.new("Unexpected section header #{line}")
        end
      end
    end

    # Standard ASF archivers
    ARCHIVERS = ["archive-asf-private@cust-asf.ponee.io", "archive-asf-public@cust-asf.ponee.io",
                 "archiver@mbox-vm.apache.org", "private@mbox-vm.apache.org", "restricted@mbox-vm.apache.org"]
    # TODO alias archivers: either add list or use RE to filter them

    LIST_MODS = '/srv/subscriptions/list-mods'

    LIST_SUBS = '/srv/subscriptions/list-subs'

    LIST_DIGS = '/srv/subscriptions/list-digs'

    # If this file exists, it is the time when the data was last extracted
    # The mods and subs files are only updated if they have changed
    LIST_TIME = '/srv/subscriptions/list-start'

  end
end

#if __FILE__ == $0
#  domain = ARGV.shift||'whimsical'
#  p  ASF::MLIST.list_subscribers(domain)
#  p  ASF::MLIST.list_subscribers(domain,false,true)
#  exit
#  p  ASF::MLIST.list_moderators(domain, true)
#  p  ASF::MLIST.private_subscribers(domain)
#  p  ASF::MLIST.digests(['chrisd@apache.org'])
#end
