@extends('layouts.app')

@section('content')
<div class="container py-4">
    <div class="row justify-content-center">
        <div class="col-md-8">
            <div class="card shadow-sm">
                <div class="card-header bg-primary text-white">
                    {{ $post->title ?? $post->name }}
                </div>
                <div class="card-body">
                    {!! $post->content !!}
                </div>
            </div>
        </div>
    </div>
</div>
@endsection
