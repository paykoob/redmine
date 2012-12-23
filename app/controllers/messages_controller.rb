# Redmine - project management software
# Copyright (C) 2006-2012  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

class MessagesController < ApplicationController
  menu_item :boards
  default_search_scope :messages
  before_filter :find_board, :only => [:new, :preview]
  before_filter :find_attachments, :only => [:preview]
  before_filter :find_message, :except => [:new, :preview]
  before_filter :authorize, :except => [:preview, :edit, :destroy]

  helper :boards
  helper :watchers
  helper :attachments
  include AttachmentsHelper

  REPLIES_PER_PAGE = 25 unless const_defined?(:REPLIES_PER_PAGE)

  # Show a topic and its replies
  def show
    page = params[:page]
    # Find the page of the requested reply
    if params[:r] && page.nil?
      offset = @topic.children.count(:conditions => ["#{Message.table_name}.id < ?", params[:r].to_i])
      page = 1 + offset / REPLIES_PER_PAGE
    end

    @reply_count = @topic.children.count
    @reply_pages = Paginator.new self, @reply_count, REPLIES_PER_PAGE, page
    @replies =  @topic.children.
      includes(:author, :attachments, {:board => :project}).
      reorder("#{Message.table_name}.created_on ASC").
      limit(@reply_pages.items_per_page).
      offset(@reply_pages.current.offset).
      all

    @reply = Message.new(:subject => "RE: #{@message.subject}")
    render :action => "show", :layout => false if request.xhr?
  end

  # Create a new topic
  def new
    @message = Message.new
    @message.author = User.current
    @message.board = @board
    @message.safe_attributes = params[:message]
    if request.post?
      @message.save_attachments(params[:attachments])
      if @message.save
        call_hook(:controller_messages_new_after_save, { :params => params, :message => @message})
        render_attachment_warning_if_needed(@message)
        redirect_to board_message_path(@board, @message)
      end
    end
  end

  # Reply to a topic
  def reply
    @reply = Message.new
    @reply.author = User.current
    @reply.board = @board
    @reply.safe_attributes = params[:reply]
    @topic.children << @reply
    if !@reply.new_record?
      call_hook(:controller_messages_reply_after_save, { :params => params, :message => @reply})
      attachments = Attachment.attach_files(@reply, params[:attachments])
      render_attachment_warning_if_needed(@reply)
    end
    redirect_to board_message_path(@board, @topic, :r => @reply)
  end

  # Edit a message
  def edit
    (render_403; return false) unless @message.editable_by?(User.current)
    @message.safe_attributes = params[:message]
    if request.post? && @message.save
      attachments = Attachment.attach_files(@message, params[:attachments])
      render_attachment_warning_if_needed(@message)
      flash[:notice] = l(:notice_successful_update)
      @message.reload
      redirect_to board_message_path(@message.board, @message.root, :r => (@message.parent_id && @message.id))
    end
  end

  # Delete a messages
  def destroy
    (render_403; return false) unless @message.destroyable_by?(User.current)
    r = @message.to_param
    @message.destroy
    if @message.parent
      redirect_to board_message_path(@board, @message.parent, :r => r)
    else
      redirect_to project_board_path(@project, @board)
    end
  end

  def quote
    @subject = @message.subject
    @subject = "RE: #{@subject}" unless @subject.starts_with?('RE:')

    @content = "#{ll(Setting.default_language, :text_user_wrote, @message.author)}\n> "
    @content << @message.content.to_s.strip.gsub(%r{<pre>((.|\s)*?)</pre>}m, '[...]').gsub(/(\r?\n|\r\n?)/, "\n> ") + "\n\n"
  end

  def preview
    message = @board.messages.find_by_id(params[:id])
    @text = (params[:message] || params[:reply])[:content]
    @previewed = message
    render :partial => 'common/preview'
  end

private
  def find_message
    find_board
    @message = @board.messages.find(params[:id], :include => :parent)
    @topic = @message.root
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_board
    @board = Board.find(params[:board_id], :include => :project)
    @project = @board.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
