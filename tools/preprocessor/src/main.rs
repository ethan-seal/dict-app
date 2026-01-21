//! Dictionary preprocessor tool
//!
//! Converts Wiktionary JSONL exports from kaikki.org into optimized SQLite databases.
//!
//! # Usage
//!
//! ```bash
//! # Raw JSONL file
//! dict-preprocessor --input kaikki-english.jsonl --output english-dict.db
//!
//! # Gzip-compressed JSONL file
//! dict-preprocessor --input kaikki-english.jsonl.gz --output english-dict.db
//!
//! # Process and upload to CDN
//! dict-preprocessor --input kaikki-english.jsonl.gz --output english-dict.db --upload --language english
//! ```

use std::fs::File;
use std::io::{BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Instant;

use anyhow::{Context, Result};
use clap::Parser;
use indicatif::{HumanBytes, HumanDuration, ProgressBar, ProgressStyle};
use s3::bucket::Bucket;
use s3::creds::Credentials;
use s3::region::Region;

/// Dictionary preprocessor - converts Wiktionary JSONL to SQLite
#[derive(Parser, Debug)]
#[command(name = "dict-preprocessor")]
#[command(
    author,
    version,
    about = "Convert Wiktionary JSONL exports to optimized SQLite databases"
)]
#[command(long_about = "
Converts Wiktionary JSONL exports from kaikki.org into optimized SQLite databases.

Supports both raw JSONL files and gzip-compressed files (.jsonl.gz).

Example usage:
  dict-preprocessor -i kaikki-english.jsonl.gz -o english.db
  dict-preprocessor --input data.jsonl --output dict.db --force
  dict-preprocessor -i data.jsonl -o dict.db --upload --language english
")]
struct Args {
    /// Input JSONL file path (supports .jsonl and .jsonl.gz)
    #[arg(short, long)]
    input: PathBuf,

    /// Output SQLite database path
    #[arg(short, long)]
    output: PathBuf,

    /// Overwrite existing output file
    #[arg(long, default_value = "false")]
    force: bool,

    /// Quiet mode - suppress progress bar
    #[arg(short, long, default_value = "false")]
    quiet: bool,

    /// Upload compressed database to CDN after processing
    #[arg(long, default_value = "false")]
    upload: bool,

    /// Language code for the database (used in CDN path, e.g., "english")
    #[arg(short, long)]
    language: Option<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Load .env file if present
    dotenvy::dotenv().ok();

    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let args = Args::parse();

    // Validate input file exists
    if !args.input.exists() {
        anyhow::bail!("Input file does not exist: {:?}", args.input);
    }

    // Validate upload args
    if args.upload && args.language.is_none() {
        anyhow::bail!("--language is required when using --upload");
    }

    // Check if output exists
    if args.output.exists() && !args.force {
        anyhow::bail!(
            "Output file already exists: {:?}. Use --force to overwrite.",
            args.output
        );
    }

    // Remove existing output if force is set
    if args.output.exists() && args.force {
        std::fs::remove_file(&args.output).context("Failed to remove existing output file")?;
    }

    // Get input file size for reporting
    let input_size = std::fs::metadata(&args.input).map(|m| m.len()).unwrap_or(0);

    println!("Input:  {:?} ({})", args.input, HumanBytes(input_size));
    println!("Output: {:?}", args.output);
    println!();

    log::info!("Starting import from {:?} to {:?}", args.input, args.output);

    let start_time = Instant::now();

    // Set up progress bar
    let total = Arc::new(AtomicU64::new(0));

    let pb = if args.quiet {
        ProgressBar::hidden()
    } else {
        ProgressBar::new(0)
    };
    pb.set_style(
        ProgressStyle::default_bar()
            .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}/{len} lines ({eta})")?
            .progress_chars("#>-"),
    );

    let total_clone = total.clone();
    let pb_clone = pb.clone();

    // Run import with progress callback
    let progress_callback = move |current: u64, total_lines: u64| {
        // Update total on first call
        if total_clone.load(Ordering::Relaxed) == 0 && total_lines > 0 {
            total_clone.store(total_lines, Ordering::Relaxed);
            pb_clone.set_length(total_lines);
        }

        pb_clone.set_position(current);
    };

    let stats = dict_core::import_jsonl_with_stats(
        args.output.to_str().context("Invalid output path")?,
        args.input.to_str().context("Invalid input path")?,
        progress_callback,
    )
    .context("Import failed")?;

    pb.finish_and_clear();

    let elapsed = start_time.elapsed();

    // Get output file size
    let output_size = std::fs::metadata(&args.output)
        .map(|m| m.len())
        .unwrap_or(0);

    // Print statistics
    println!("Import complete!");
    println!();
    println!("Statistics:");
    println!(
        "  Lines processed:    {:>12}",
        format_number(stats.lines_processed)
    );
    println!(
        "  Words imported:     {:>12}",
        format_number(stats.words_imported)
    );
    println!(
        "  Definitions:        {:>12}",
        format_number(stats.definitions_imported)
    );
    println!(
        "  Pronunciations:     {:>12}",
        format_number(stats.pronunciations_imported)
    );
    println!(
        "  Etymologies:        {:>12}",
        format_number(stats.etymologies_imported)
    );
    println!(
        "  Translations:       {:>12}",
        format_number(stats.translations_imported)
    );
    println!("  Errors:             {:>12}", format_number(stats.errors));
    println!("  Skipped:            {:>12}", format_number(stats.skipped));
    println!();
    println!("Performance:");
    println!("  Time elapsed:       {:>12}", HumanDuration(elapsed));
    println!("  Output size:        {:>12}", HumanBytes(output_size));

    if elapsed.as_secs() > 0 {
        let lines_per_sec = stats.lines_processed / elapsed.as_secs();
        println!("  Lines/second:       {:>12}", format_number(lines_per_sec));
    }

    log::info!(
        "Successfully imported {} words to {:?} in {:?}",
        stats.words_imported,
        args.output,
        elapsed
    );

    // Upload to CDN if requested
    if args.upload {
        let language = args.language.as_ref().unwrap();
        println!();
        println!("Uploading to CDN...");

        // Compress with zstd
        let compressed_path = args.output.with_extension("db.zst");
        println!("  Compressing database...");
        compress_zstd(&args.output, &compressed_path)?;

        let compressed_size = std::fs::metadata(&compressed_path)
            .map(|m| m.len())
            .unwrap_or(0);
        println!(
            "  Compressed: {} -> {} ({:.1}% reduction)",
            HumanBytes(output_size),
            HumanBytes(compressed_size),
            (1.0 - compressed_size as f64 / output_size as f64) * 100.0
        );

        // Upload to S3
        let cdn_key = format!("{}-dict.db.zst", language);
        println!("  Uploading as '{}'...", cdn_key);
        upload_to_cdn(&compressed_path, &cdn_key).await?;

        // Clean up compressed file
        std::fs::remove_file(&compressed_path).ok();

        println!("  Upload complete!");
    }

    Ok(())
}

/// Compress a file using zstd
fn compress_zstd(input: &Path, output: &Path) -> Result<()> {
    let input_file = File::open(input).context("Failed to open input file for compression")?;
    let mut reader = BufReader::new(input_file);

    let output_file = File::create(output).context("Failed to create compressed output file")?;
    let writer = BufWriter::new(output_file);

    // Use compression level 19 for good compression (max is 22)
    let mut encoder = zstd::Encoder::new(writer, 19)?;

    let mut buffer = vec![0u8; 64 * 1024];
    loop {
        let bytes_read = reader.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        encoder.write_all(&buffer[..bytes_read])?;
    }

    encoder.finish()?;
    Ok(())
}

/// Upload a file to the CDN (S3-compatible storage)
async fn upload_to_cdn(file_path: &Path, key: &str) -> Result<()> {
    // Read credentials from environment
    let access_key_id =
        std::env::var("CDN_ACCESS_KEY_ID").context("CDN_ACCESS_KEY_ID not set in environment")?;
    let secret_access_key =
        std::env::var("CDN_ACCESS_KEY").context("CDN_ACCESS_KEY not set in environment")?;
    let cdn_url = std::env::var("CDN_URL").context("CDN_URL not set in environment")?;

    // Parse CDN URL to extract bucket and region
    // Expected format: https://{bucket}.{region}.digitaloceanspaces.com
    let url = url::Url::parse(&cdn_url).context("Invalid CDN_URL")?;
    let host = url.host_str().context("CDN_URL missing host")?;

    let parts: Vec<&str> = host.split('.').collect();
    if parts.len() < 3 {
        anyhow::bail!(
            "CDN_URL must be in format: https://{{bucket}}.{{region}}.digitaloceanspaces.com"
        );
    }

    let bucket_name = parts[0];
    let region_name = parts[1];
    let endpoint = format!("https://{}.digitaloceanspaces.com", region_name);

    log::info!(
        "Uploading to bucket '{}' in region '{}' with key '{}'",
        bucket_name,
        region_name,
        key
    );

    // Create credentials and region
    let credentials = Credentials::new(
        Some(&access_key_id),
        Some(&secret_access_key),
        None,
        None,
        None,
    )?;

    let region = Region::Custom {
        region: region_name.to_string(),
        endpoint,
    };

    // Create bucket handle with public-read ACL header
    let mut bucket = Bucket::new(bucket_name, region, credentials)?.with_path_style();
    bucket.add_header("x-amz-acl", "public-read");

    // Read file contents
    let contents = std::fs::read(file_path).context("Failed to read file for upload")?;

    // Upload
    let response = bucket
        .put_object_with_content_type(key, &contents, "application/octet-stream")
        .await?;

    if response.status_code() >= 300 {
        anyhow::bail!(
            "Upload failed with status {}: {}",
            response.status_code(),
            String::from_utf8_lossy(response.as_slice())
        );
    }

    log::info!("Successfully uploaded {} to CDN", key);
    Ok(())
}

/// Format a number with thousand separators
fn format_number(n: u64) -> String {
    let s = n.to_string();
    let mut result = String::new();
    for (i, c) in s.chars().rev().enumerate() {
        if i > 0 && i % 3 == 0 {
            result.push(',');
        }
        result.push(c);
    }
    result.chars().rev().collect()
}
