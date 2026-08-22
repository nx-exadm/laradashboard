<x-layouts.backend-layout :breadcrumbs="$breadcrumbs ?? []">

    <div class="mb-6 w-full flex flex-nowrap items-center justify-between gap-3">
        <div class="flex items-center gap-x-2 min-w-0 flex-1">
            <span class="inline-flex items-center justify-center w-9 h-9 shrink-0 rounded-lg bg-gray-100 dark:bg-gray-800 text-gray-500 dark:text-gray-400">
                <iconify-icon icon="lucide:database" width="20" height="20"></iconify-icon>
            </span>
            <iconify-icon icon="lucide:chevron-right" width="16" height="16" class="text-gray-400 dark:text-gray-500 shrink-0"></iconify-icon>
            <h2 class="text-xl font-semibold text-gray-700 dark:text-white/90 flex items-center gap-2 min-w-0">
                <span class="truncate">{{ __('Database Info') }}</span>
            </h2>
        </div>

        <div class="flex items-center gap-2 shrink-0">
            <form method="GET" action="{{ url()->current() }}">
                <button type="submit" class="btn-secondary flex items-center gap-2">
                    <iconify-icon icon="lucide:refresh-cw" height="16"></iconify-icon>
                    {{ __('Refresh') }}
                </button>
            </form>
        </div>
    </div>

    {{-- Top summary cards --}}
    <div class="grid grid-cols-2 gap-4 mb-6 md:grid-cols-4 md:gap-6">
        <div class="p-4 bg-white rounded-md border border-gray-200 dark:border-gray-800 dark:bg-white/[0.03]">
            <div class="flex items-center">
                <iconify-icon icon="lucide:hard-drive" class="text-2xl text-blue-500 mr-3"></iconify-icon>
                <div>
                    <p class="text-sm text-gray-500 dark:text-gray-300">{{ __('Database Size') }}</p>
                    <p class="text-lg font-semibold text-gray-700 dark:text-white">{{ $databaseInfo['size_formatted'] }}</p>
                </div>
            </div>
        </div>

        <div class="p-4 bg-white rounded-md border border-gray-200 dark:border-gray-800 dark:bg-white/[0.03]">
            <div class="flex items-center">
                <iconify-icon icon="lucide:table" class="text-2xl text-purple-500 mr-3"></iconify-icon>
                <div>
                    <p class="text-sm text-gray-500 dark:text-gray-300">{{ __('Tables') }}</p>
                    <p class="text-lg font-semibold text-gray-700 dark:text-white">{{ number_format($databaseInfo['tables_count']) }}</p>
                </div>
            </div>
        </div>

        <div class="p-4 bg-white rounded-md border border-gray-200 dark:border-gray-800 dark:bg-white/[0.03]">
            <div class="flex items-center">
                <iconify-icon icon="lucide:rows-3" class="text-2xl text-green-500 mr-3"></iconify-icon>
                <div>
                    <p class="text-sm text-gray-500 dark:text-gray-300">{{ __('Total Rows') }}</p>
                    <p class="text-lg font-semibold text-gray-700 dark:text-white">{{ number_format($databaseInfo['total_rows']) }}</p>
                </div>
            </div>
        </div>

        <div class="p-4 bg-white rounded-md border border-gray-200 dark:border-gray-800 dark:bg-white/[0.03]">
            <div class="flex items-center">
                <iconify-icon icon="lucide:zap" class="text-2xl text-amber-500 mr-3"></iconify-icon>
                <div>
                    <p class="text-sm text-gray-500 dark:text-gray-300">{{ __('Query Response') }}</p>
                    <p class="text-lg font-semibold text-gray-700 dark:text-white">{{ $queryTimeMs }} ms</p>
                </div>
            </div>
        </div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">

        {{-- Disk usage --}}
        <div class="lg:col-span-1 rounded-md border border-gray-200 dark:border-gray-800 bg-white dark:bg-white/[0.03]">
            <div class="px-5 py-4 sm:px-6 sm:py-5 border-b border-gray-100 dark:border-gray-800">
                <h3 class="font-semibold text-gray-700 dark:text-white flex items-center gap-2">
                    <iconify-icon icon="lucide:pie-chart" width="18" height="18"></iconify-icon>
                    {{ __('Disk Usage') }}
                </h3>
                <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">{{ __('Partition hosting the database & storage') }}</p>
            </div>

            <div class="p-5 sm:p-6 space-y-4">
                @php
                    $usedPercent = $diskInfo['used_percent'];
                    $barColor = $usedPercent >= 90
                        ? 'bg-red-500'
                        : ($usedPercent >= 75 ? 'bg-amber-500' : 'bg-green-500');
                @endphp

                <div>
                    <div class="flex justify-between text-sm mb-2">
                        <span class="text-gray-600 dark:text-gray-300">
                            {{ $diskInfo['used_formatted'] }} {{ __('used') }}
                        </span>
                        <span class="font-medium text-gray-700 dark:text-white">{{ $usedPercent }}%</span>
                    </div>
                    <div class="w-full h-3 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden">
                        <div class="h-full {{ $barColor }} transition-all duration-500" style="width: {{ min($usedPercent, 100) }}%"></div>
                    </div>
                </div>

                <div class="grid grid-cols-2 gap-4 pt-2">
                    <div>
                        <p class="text-xs text-gray-500 dark:text-gray-400">{{ __('Free Space') }}</p>
                        <p class="text-sm font-semibold text-gray-700 dark:text-white">{{ $diskInfo['free_formatted'] }}</p>
                    </div>
                    <div>
                        <p class="text-xs text-gray-500 dark:text-gray-400">{{ __('Total Capacity') }}</p>
                        <p class="text-sm font-semibold text-gray-700 dark:text-white">{{ $diskInfo['total_formatted'] }}</p>
                    </div>
                </div>

                @if ($usedPercent >= 90)
                    <div class="flex items-start gap-2 p-3 rounded-md bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
                        <iconify-icon icon="lucide:alert-triangle" class="text-red-500 mt-0.5" width="16" height="16"></iconify-icon>
                        <p class="text-xs text-red-700 dark:text-red-300">
                            {{ __('Disk space is critically low. Consider freeing up space or expanding storage soon.') }}
                        </p>
                    </div>
                @elseif ($usedPercent >= 75)
                    <div class="flex items-start gap-2 p-3 rounded-md bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800">
                        <iconify-icon icon="lucide:alert-circle" class="text-amber-500 mt-0.5" width="16" height="16"></iconify-icon>
                        <p class="text-xs text-amber-700 dark:text-amber-300">
                            {{ __('Disk usage is getting high. Worth keeping an eye on.') }}
                        </p>
                    </div>
                @endif
            </div>
        </div>

        {{-- Connection info --}}
        <div class="lg:col-span-1 rounded-md border border-gray-200 dark:border-gray-800 bg-white dark:bg-white/[0.03]">
            <div class="px-5 py-4 sm:px-6 sm:py-5 border-b border-gray-100 dark:border-gray-800">
                <h3 class="font-semibold text-gray-700 dark:text-white flex items-center gap-2">
                    <iconify-icon icon="lucide:plug" width="18" height="18"></iconify-icon>
                    {{ __('Connection') }}
                </h3>
                <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">{{ __('Active database driver details') }}</p>
            </div>

            <div class="p-5 sm:p-6">
                <dl class="space-y-3 text-sm">
                    <div class="flex justify-between">
                        <dt class="text-gray-500 dark:text-gray-400">{{ __('Driver') }}</dt>
                        <dd class="font-medium text-gray-700 dark:text-white">{{ strtoupper($databaseInfo['driver']) }}</dd>
                    </div>
                    <div class="flex justify-between">
                        <dt class="text-gray-500 dark:text-gray-400">{{ __('Status') }}</dt>
                        <dd class="inline-flex items-center gap-1.5 font-medium text-green-600 dark:text-green-400">
                            <span class="w-1.5 h-1.5 rounded-full bg-green-500"></span>
                            {{ __('Connected') }}
                        </dd>
                    </div>
                    <div class="flex justify-between">
                        <dt class="text-gray-500 dark:text-gray-400">{{ __('PHP Version') }}</dt>
                        <dd class="font-medium text-gray-700 dark:text-white">{{ PHP_VERSION }}</dd>
                    </div>
                    <div class="flex justify-between">
                        <dt class="text-gray-500 dark:text-gray-400">{{ __('Laravel Version') }}</dt>
                        <dd class="font-medium text-gray-700 dark:text-white">{{ app()->version() }}</dd>
                    </div>
                    <div class="flex justify-between">
                        <dt class="text-gray-500 dark:text-gray-400">{{ __('Environment') }}</dt>
                        <dd class="font-medium text-gray-700 dark:text-white">{{ ucfirst(app()->environment()) }}</dd>
                    </div>
                </dl>
            </div>
        </div>

        {{-- Largest tables --}}
        <div class="lg:col-span-1 rounded-md border border-gray-200 dark:border-gray-800 bg-white dark:bg-white/[0.03]">
            <div class="px-5 py-4 sm:px-6 sm:py-5 border-b border-gray-100 dark:border-gray-800">
                <h3 class="font-semibold text-gray-700 dark:text-white flex items-center gap-2">
                    <iconify-icon icon="lucide:bar-chart-3" width="18" height="18"></iconify-icon>
                    {{ __('Largest Tables') }}
                </h3>
                <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">{{ __('By row count, top 8') }}</p>
            </div>

            <div class="p-5 sm:p-6">
                @if (count($databaseInfo['tables']) > 0)
                    <ul class="space-y-3">
                        @foreach (array_slice($databaseInfo['tables'], 0, 8) as $table)
                            <li class="flex items-center justify-between text-sm">
                                <span class="text-gray-700 dark:text-gray-300 truncate font-mono text-xs">{{ $table['name'] }}</span>
                                <span class="font-medium text-gray-700 dark:text-white shrink-0 ml-3">{{ number_format($table['rows']) }}</span>
                            </li>
                        @endforeach
                    </ul>
                @else
                    <p class="text-sm text-gray-500 dark:text-gray-400">{{ __('No tables found.') }}</p>
                @endif
            </div>
        </div>
    </div>

    {{-- Full table breakdown --}}
    <div class="mt-6 rounded-md border border-gray-200 dark:border-gray-800 bg-white dark:bg-white/[0.03]">
        <div class="px-5 py-4 sm:px-6 sm:py-5 border-b border-gray-100 dark:border-gray-800">
            <h3 class="font-semibold text-gray-700 dark:text-white flex items-center gap-2">
                <iconify-icon icon="lucide:list" width="18" height="18"></iconify-icon>
                {{ __('All Tables') }}
            </h3>
        </div>

        <div class="overflow-x-auto">
            <table class="table">
                <thead class="table-thead">
                    <tr class="table-tr">
                        <th class="table-thead-th">{{ __('Table') }}</th>
                        <th class="table-thead-th table-thead-th-last">{{ __('Row Count') }}</th>
                    </tr>
                </thead>
                <tbody class="table-tbody">
                    @forelse ($databaseInfo['tables'] as $table)
                        <tr class="table-tr">
                            <td class="table-td font-mono text-xs">{{ $table['name'] }}</td>
                            <td class="table-td">{{ number_format($table['rows']) }}</td>
                        </tr>
                    @empty
                        <tr class="table-tr">
                            <td class="table-td text-center text-gray-500 dark:text-gray-400" colspan="2">
                                {{ __('No tables found.') }}
                            </td>
                        </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

</x-layouts.backend-layout>
