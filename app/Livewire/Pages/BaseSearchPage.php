```php
<?php

declare(strict_types=1);

namespace App\Livewire\Pages;

use App\Models\Post;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Livewire\Attributes\Url;
use Livewire\WithPagination;

abstract class BaseSearchPage extends BaseFrontendPage
{
    use WithPagination;

    #[Url(as: 'q')]
    public string $query = '';

    public function updatedQuery(): void
    {
        $this->resetPage();
    }

    /**
     * Get paginated published page search results.
     *
     * Search is performed against:
     * - Page title
     * - Page meta description/excerpt
     *
     * The page content is intentionally NOT searched or returned.
     */
    public function getResultsProperty(): ?LengthAwarePaginator
    {
        $query = trim($this->query);

        if ($query === '') {
            return null;
        }

        return Post::query()
            ->where('post_type', 'page')
            ->where('status', 'published')
            ->where(function ($builder) use ($query) {
                $builder
                    ->where('title', 'like', '%' . $query . '%')
                    ->orWhere('excerpt', 'like', '%' . $query . '%');
            })
            ->select([
                'id',
                'title',
                'slug',
                'excerpt',
            ])
            ->orderBy('title')
            ->paginate(12);
    }

    /**
     * Clear the current search.
     */
    public function clearSearch(): void
    {
        $this->query = '';
        $this->resetPage();
    }
}
```
