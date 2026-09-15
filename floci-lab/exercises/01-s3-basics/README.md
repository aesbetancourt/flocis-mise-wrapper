# Exercise 01 — S3 basics

| Level | Services | Time |
| --- | --- | --- |
| 1 | S3 | 30–45 minutes |

## Goal

Build a versioned bucket for notes. Old versions of each note expire after 30
days. Then write and read versions from code.

## What you learn

- The OpenTofu loop: `init`, `plan`, `apply`, `destroy`.
- S3 buckets, objects, versioning, and lifecycle rules.
- Why a delete in a versioned bucket does not remove the data.
- Why `tofu destroy` can fail on a bucket, and how to fix it.

## Before you start

1. Make sure the lab runs:

   ```bash
   mise run health
   ```

2. Go to this folder:

   ```bash
   cd floci-lab/exercises/01-s3-basics
   ```

---

## Part A — Explore with the AWS CLI

Learn how versioning works before you write code.

1. Create a bucket and turn on versioning:

   ```bash
   aws s3 mb s3://ex01-cli-demo
   aws s3api put-bucket-versioning --bucket ex01-cli-demo \
     --versioning-configuration Status=Enabled
   ```

2. Upload the same key two times with different content:

   ```bash
   echo "v1" | aws s3 cp - s3://ex01-cli-demo/draft.txt
   echo "v2" | aws s3 cp - s3://ex01-cli-demo/draft.txt
   ```

3. List the versions:

   ```bash
   aws s3api list-object-versions --bucket ex01-cli-demo \
     --query 'Versions[].{Id:VersionId,Latest:IsLatest}' --output table
   ```

4. Read the old version. Replace `<version-id>` with the ID where `Latest` is
   `False`:

   ```bash
   aws s3api get-object --bucket ex01-cli-demo --key draft.txt \
     --version-id <version-id> old.txt && cat old.txt && rm old.txt
   ```

5. Delete the object, then list the versions again:

   ```bash
   aws s3 rm s3://ex01-cli-demo/draft.txt
   aws s3api list-object-versions --bucket ex01-cli-demo
   ```

   **Question:** The object is deleted. Why do both versions still exist? What
   is the new `DeleteMarkers` entry?

6. Remove the bucket:

   ```bash
   aws s3 rb s3://ex01-cli-demo --force
   ```

> **Note:** On Floci, this command removes the bucket. On real AWS, it fails
> with `BucketNotEmpty`, because `--force` deletes only the latest versions. Old
> versions and delete markers stay. This is one of the places where the
> emulator is less strict than AWS.

---

## Part B — Build with OpenTofu

1. Initialize OpenTofu. The flag reuses the provider that the lab already
   downloaded:

   ```bash
   tofu init -plugin-dir=../../.terraform/providers
   ```

2. Open `main.tf`. Complete TODO 1 to TODO 5.
3. Preview the changes after each TODO:

   ```bash
   tofu plan
   ```

4. Apply the changes:

   ```bash
   tofu apply
   ```

5. Read the output:

   ```bash
   tofu output bucket_name
   ```

6. Run `tofu plan` again. It must show `No changes`.

---

## Part C — Use it from code

1. Open `app.py`. Complete TODO 1 to TODO 3.
2. Run the app:

   ```bash
   uv run --with boto3 python app.py
   ```

   The output must show two versions and the content `first draft`.

3. Run the app a second time. **Question:** How many versions exist now? Why?

---

## Check your work

```bash
./check.sh
```

The checker reads the emulator, not your files. All checks must show `PASS`.

---

## Clean up

1. Destroy the resources:

   ```bash
   tofu destroy
   ```

2. The command fails with `BucketNotEmpty`. **Question:** OpenTofu created one
   object. Which objects did it not create?

3. Fix the problem. Add `force_destroy = true` to the bucket, then apply and
   destroy again:

   ```bash
   tofu apply
   tofu destroy
   ```

> **Caution:** On a real account, `force_destroy` deletes all objects and
> versions without a second question. Use it for labs and test buckets only.

> **Note:** `force_destroy` works here because the bucket has versioning. On
> Floci 2.1.0, it does not end for a bucket without versioning that holds
> objects. For such a bucket, run `aws s3 rm s3://<bucket> --recursive` before
> `tofu destroy`. Exercise 04 shows this.

---

## Stretch goals

- Add a second lifecycle rule. It moves current objects under `archive/` to the
  `GLACIER` storage class after 90 days.
- Add a bucket policy that denies requests without HTTPS
  (`aws:SecureTransport`).
- Upload every file in a local folder with `for_each` and `fileset()`.
- In `app.py`, restore the oldest version: copy it over the latest version with
  `copy_object`.

---

## Hints

<details>
<summary>tofu init fails: the provider is not in the plugin directory</summary>

The lab provider is not downloaded yet. Run `tofu init` in `floci-lab/` once,
or run `mise run install`. Then run the init command of this exercise again.

</details>

<details>
<summary>TODO 3: which rule settings to use</summary>

Use a `rule` block with `id`, `status = "Enabled"`, an empty `filter {}`, and a
`noncurrent_version_expiration` block. An empty `filter` applies the rule to
every object.

</details>

<details>
<summary>Why the solution has depends_on</summary>

On real AWS, a lifecycle rule for old versions can fail when versioning is not
active yet. The provider documentation recommends
`depends_on = [aws_s3_bucket_versioning.<name>]`. Floci does not need it, but
the habit prevents a failure on a real account.

</details>

<details>
<summary>check.sh: "notes/today.txt has at least 2 versions" fails</summary>

Run Part C. The checker looks for the versions that `app.py` uploads.

</details>

<details>
<summary>The app fails with NoSuchBucket</summary>

Apply Part B first. The app uses the bucket that OpenTofu creates.

</details>

---

## Solution

Try the exercise first. The solution is in [`solution/`](solution/).

To run the solution, destroy your own resources first. Both use the same bucket
name.

```bash
cd solution
tofu init -plugin-dir=../../../.terraform/providers
tofu apply
uv run --with boto3 python app.py
../check.sh
tofu destroy
```
