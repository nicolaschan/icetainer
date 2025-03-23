use std::path::Path;
use std::time::Duration;
use std::os::unix::net::UnixStream;
use anyhow::{Context, Result};
use qapi::{self, Qmp, Qga};

fn main() -> Result<()> {
    // Configuration
    let qga_socket_path = "/tmp/qga.sock";
    let qmp_socket_path = "/tmp/qemu-sock";
    let snapshot_name = "vm_snapshot_latest".to_string();
    let timeout_duration = Duration::from_secs(30);
    
    // Verify socket paths exist
    if !Path::new(qga_socket_path).exists() {
        anyhow::bail!("QGA socket {} does not exist", qga_socket_path);
    }
    
    if !Path::new(qmp_socket_path).exists() {
        anyhow::bail!("QMP socket {} does not exist", qmp_socket_path);
    }
    
    // Connect to QMP socket with standard library's synchronous UnixStream
    println!("Connecting to QMP socket...");
    let qmp_stream = UnixStream::connect(qmp_socket_path)
        .context("Failed to connect to QMP socket")?;
    
    // Set socket timeouts
    qmp_stream.set_read_timeout(Some(timeout_duration))
        .context("Failed to set read timeout")?;
    qmp_stream.set_write_timeout(Some(timeout_duration))
        .context("Failed to set write timeout")?;
    
    // Create QMP client
    let mut qmp = Qmp::from_stream(&qmp_stream);
    
    // Negotiate capabilities
    println!("Negotiating QMP capabilities...");
    qmp.read_capabilities()
        .context("Failed to negotiate QMP capabilities")?;
    
    // Connect to QGA socket
    println!("Connecting to QGA socket...");
    let qga_stream = UnixStream::connect(qga_socket_path)
        .context("Failed to connect to QGA socket")?;
    
    // Set socket timeouts
    qga_stream.set_read_timeout(Some(timeout_duration))
        .context("Failed to set read timeout")?;
    qga_stream.set_write_timeout(Some(timeout_duration))
        .context("Failed to set write timeout")?;
    
    // Create QGA client
    let mut qga = Qga::from_stream(&qga_stream);
    
    // Freeze the filesystem
    println!("Freezing filesystem...");
    let freeze_result = qga.execute(&qapi::qga::guest_fsfreeze_freeze {})
        .context("Failed to freeze filesystem")?;
    println!("Filesystem frozen successfully (frozen {} filesystems)", freeze_result);
    
    // Take snapshot using human-monitor-command (HMP passthrough)
    println!("Taking snapshot: {}...", snapshot_name);
    qmp.execute(&qapi::qmp::qmp_capabilities { enable: Some(vec![]) })
        .context("Failed to read capabilities")?;
    let snapshot_result = qmp.execute(&qapi::qmp::human_monitor_command {
        cpu_index: None,
        command_line: format!("savevm {}", snapshot_name),
    });
    
    // Always thaw filesystem, even if snapshot fails
    println!("Thawing filesystem...");
    let thaw_result = qga.execute(&qapi::qga::guest_fsfreeze_thaw {});
    
    // Check snapshot result
    let snapshot_response = snapshot_result.context("Failed to take snapshot")?;
    // For human-monitor-command, check if there's any error message in the output
    if !snapshot_response.is_empty() {
        // HMP commands that succeed often return empty strings
        // If we got something back, it might be an error message
        anyhow::bail!("Snapshot might have failed: {}", snapshot_response);
    }
    println!("Snapshot taken successfully");
    
    // Check thaw result
    let thawed_count = thaw_result.context("Failed to thaw filesystem")?;
    println!("Filesystem thawed successfully (thawed {} filesystems)", thawed_count);
    
    // Shutdown the VM
    println!("Shutting down VM...");
    qmp.execute(&qapi::qmp::system_powerdown {})
        .context("Failed to shut down VM")?;
    println!("VM shutdown initiated successfully");
    
    println!("All operations completed successfully");
    Ok(())
}
