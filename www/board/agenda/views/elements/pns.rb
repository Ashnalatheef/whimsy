#
# Determine status of podling name
#

class PodlingNameSearch < Vue
  props [:item]

  def render
    _span.pns title: 'podling name search' do
      if Server.podlingnamesearch
        if not @results
          _abbr "\u2718", title: 'No PODLINGNAMESEARCH found'
        elsif @results.resolution == 'Fixed'
          _a "\u2714", href: 'https://issues.apache.org/jira/browse/' +
            @results.issue
        else
          _a "\uFE56", href: 'https://issues.apache.org/jira/browse/' +
            @results.issue
        end
      end
    end
  end

  # initial mount: fetch podlingnamesearch data unless already downloaded
  def mounted()
    if Server.podlingnamesearch
      self.check($props)
    else
      retrieve 'podlingnamesearch', :json do |results|
        Server.podlingnamesearch = results
        self.check($props)
      end
    end
  end

  # lookup name in the establish resolution against the podlingnamesearches
  def check(props)
    @results = nil
    name = props.item.title[/Establish (.*)/, 1]

    # if full title contains a name in parenthesis, check for that name too
    altname = props.item.fulltitle[/\((.*?)\)/, 1]

    if name and Server.podlingnamesearch
      Server.podlingnamesearch.each_pair do |podling, jira|
        @results = jira if name == podling or altname == podling
      end
    end

    Vue.forceUpdate()
  end
end
