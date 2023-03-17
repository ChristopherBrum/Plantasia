# frozen_string_literal: true

# Module for pagination helper methods
module PaginationUtil
  def next_page(page_id)
    params[:page_id] = page_id.to_i + 1
  end

  def last_page
    params[:page_id].to_i - 1
  end

  def page_one?(page_id)
    page_id.to_i <= 1
  end

  def page_end?(page_id, num_of_pages)
    (page_id.to_i + 1) > num_of_pages
  end

  def find_page_numbers(page_id, num_of_pages)
    if num_of_pages <= Limits::PAGE_NUMBERS_DISPLAYED
      (1..num_of_pages).to_a
    elsif num_of_pages > Limits::PAGE_NUMBERS_DISPLAYED &&
          page_id <= Limits::PAGE_ID_MIN_THRESHOLD
      (1..Limits::PAGE_NUMBERS_DISPLAYED).to_a
    else
      find_last_page_numbers(page_id, num_of_pages)
    end
  end

  def find_last_page_numbers(page_id, num_of_pages)
    if (page_id + 1) == num_of_pages
      first = (page_id - 3)
      last = (page_id + 1)
    elsif page_id == num_of_pages
      first = (page_id - 4)
      last = page_id
    else
      first = (page_id - 2)
      last = (page_id + 2)
    end

    (first..last).to_a
  end
end
