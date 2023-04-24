#
# Modify People's role in a project
#

class PMCMod < Vue
  mixin ProjectMod
  options mod_tag: "pmcmod", mod_action: 'actions/committee'

  def initialize
    @people = []
    @votelink = ''
  end

  def render
    _div.modal.fade.pmcmod! tabindex: -1 do
      _div.modal_dialog do
        _div.modal_content do
          _div.modal_header.bg_info do
            _button.close 'x', data_dismiss: 'modal'
            _h4.modal_title "Modify People's Roles in the " +
              @@project.display_name + ' Project'
          end

          _div.modal_body do
            _div.container_fluid do
              _table.table do
                _thead do
                  _tr do
                    _th 'id'
                    _th 'name'
                  end
                end
                _tbody do
                  @people.each do |person|
                    _tr do
                      _td person.id
                      _td person.name
                    end
                  end
                end
              end
            end

            # add to PMC button is only shown if every person is not on the PMC
            if @people.all? {|person| !@@project.members.include? person.id}
              _p do
                _br
                _b do
                  _ 'Before adding a new PMC member, '
                  _a 'the PMC must approve the new member by VOTE or consensus.',
                  _a 'a VOTE thread or consensus decistion must be made on the private mail list',
                    href: 'https://www.apache.org/dev/pmc.html#newpmc'
                  _a 'You can use the following link to find the thread on the private list'
                  _a 'and copy it into the text field below.'
                    href: 'https://lists.apache.org/list?private@#{@project}.apache.org:lte=6M:'
                  _ ' (the PMC private@ mailing list).'                  
                end
                _label do
                  _span 'Enter the link to the approval VOTE or consensus thread:'
                  _input type: 'text', value:@votelink
                end
              end
            end
          end

          _div.modal_footer do
            _span.status 'Processing request...' if @disabled

            _button.btn.btn_default 'Cancel', data_dismiss: 'modal',
              disabled: @disabled

            # show add to PMC button only if every person is not on the PMC
            if @people.all? {|person| !@@project.members.include? person.id}
              _button.btn.btn_primary "Add to PMC",
                data_action: 'add pmc info',
                onClick: self.post, disabled: (@people.empty? or not @notice_elapsed)
            end

            # remove from all relevant locations
            remove_from = ['commit']
            if @people.any? {|person| @@project.members.include? person.id}
              remove_from << 'info'
            end
            if @people.any? {|person| @@project.ldap.include? person.id}
              remove_from << 'pmc'
            end

            _button.btn.btn_primary 'Remove from project', onClick: self.post,
              data_action: "remove #{remove_from.join(' ')}"

            if @people.all? {|person| @@project.members.include? person.id}
              _button.btn.btn_warning "Remove from PMC only",
                data_action: 'remove pmc info',
                onClick: self.post
            end
          end
        end
      end
    end
  end
end
